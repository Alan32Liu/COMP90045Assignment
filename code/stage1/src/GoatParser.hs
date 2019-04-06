module GoatParser where

import GoatAST

import Text.Parsec
import Text.Parsec.Expr
import Text.Parsec.Language
import qualified Text.Parsec.Token as Token

type Parser a
   = Parsec String Int a

-- ----------------------------------------------------------------------------
-- Token parser generation

reservedNames = [ "begin", "bool", "call", "do", "else", "end", "false", "fi"
                , "float", "if", "int", "od", "proc", "read", "ref", "then"
                , "true", "val", "while", "write"
                ]
reservedOpNames = [ ":=" -- assignment
                  -- other operators:
                  , "||"                            -- boolean disjunction (left)
                  , "&&"
                  , "!"
                  , "=", "!=", "<", "<=", ">", ">=" -- relational (not associative)
                  , "+", "-"
                  , "*", "/"
                  , "-"
                  ]
languageDef
  = emptyDef { Token.commentLine     = "#"
             , Token.identStart      = letter                  -- [a-zA-Z]
             , Token.identLetter     = alphaNum <|> oneOf "_'" -- [a-zA-Z0-9_']
             , Token.opLetter        = oneOf "<-&*!|/>+=:"
             , Token.reservedNames   = reservedNames
             , Token.reservedOpNames = reservedOpNames
             }

lexer = Token.makeTokenParser languageDef

-- Token and lexer help us define a bunch of helpful parsers for tokens:

semi       = Token.semi       lexer -- parses a semicolon
whiteSpace = Token.whiteSpace lexer -- parses whitespace
comma      = Token.comma      lexer -- parse a single comma
identifier = Token.identifier lexer -- parses an identifier

reserved   = Token.reserved   lexer -- parses a reserved name
reservedOp = Token.reservedOp lexer -- partses an operator

lexeme     = Token.lexeme     lexer -- parse and then consume trailling spaces
parens     = Token.parens     lexer -- parse inside parens
brackets   = Token.brackets   lexer -- parse inside brackets
commaSep   = Token.commaSep   lexer -- parse a comma-separated list


-- TODO: replace these with our own parsers that do not permit non-digits
-- like in 0x42 and 3.14e-7 (and escape sequences for strings)
integer       = Token.integer       lexer
float         = Token.float         lexer
stringLiteral = Token.stringLiteral lexer
-- E.g.:
-- digit = oneOf "0123456789"
-- integer = (lexeme $ many1 digit) >>= (\s -> return (read s :: Int))
-- float   = (lexeme $ (many1 digit >> char "." >> many1 digit))
-- Actually Token.decimal behaves like we want integer to behave.

-- ----------------------------------------------------------------------------
-- Program parsing


parseProgram
  = between whiteSpace eof parseGoatProgram

-- GOAT       -> PROC+
parseGoatProgram :: Parser GoatProgram
parseGoatProgram
  = do
      procs <- many1 pProc
      return (GoatProgram procs)

-- PROC       -> "proc" id "(" PARAMS ")" DECL* "begin" STMT+ "end"
-- PARAMS     -> (PARAM ",")* PARAM | ε
pProc :: Parser Proc
pProc
  = do
      reserved "proc"
      name <- identifier
      params <- parens (commaSep pParam)
      decls <- many pDecl
      reserved "begin"
      stmts <- many1 pStmt
      reserved "end"
      return (Proc name params decls stmts)

-- PARAM      -> PASSBY TYPE id
pParam :: Parser Param
pParam
  = do
      passBy <- pPassBy
      baseType <- pBaseType
      name <- identifier
      return (Param passBy baseType name)

-- PASSBY     -> "val" | "ref"
pPassBy :: Parser PassBy
pPassBy
  =   reserved "val" >> return Val -- Look for other methods of doing this?
  <|> reserved "ref" >> return Ref -- for example, consider making PassBy an
                                   -- instance of the Read typeclass or something?

-- TYPE       -> "bool" | "float" | "int"
pBaseType :: Parser BaseType
pBaseType
  =   reserved "bool"  >> return BoolType
  <|> reserved "float" >> return FloatType
  <|> reserved "int"   >> return IntType

-- DECL       -> TYPE id DECL_SHAPE ";"
pDecl :: Parser Decl
pDecl
  = do
      baseType <- pBaseType
      name <- identifier
      dim <- pDim
      semi
      return (Decl baseType name dim)


-- STMT       -> ASGN | READ | WRITE | CALL | IF | WHILE 
pStmt :: Parser Stmt
pAgn, pRead, pWrite, pCall, pIf, pWhile :: Parser Stmt
pStmt
  = choice [pAsg, pRead, pWrite, pCall, pIf, pWhile]


-- ASGN       -> SHAPED_ID ":=" EXPR ";"
pAsg
  = do
      var <- pVar
      reservedOp ":="
      expr <- pExpr
      semi
      return (Asg var expr)

-- READ       -> "read" SHAPED_ID ";"
pRead
  = do
      reserved "read"
      var <- pVar
      semi
      return (Read var)

-- WRITE      -> "write" EXPR ";"
pWrite
  = do
      reserved "write"
      expr <- pExpr
      semi
      return (Write expr)

-- CALL       -> "call" id "(" EXPRS ")" ";"
-- EXPRS      -> (EXPR ",")* EXPR | ε
pCall
  = do
      reserved "call"
      name <- identifier
      args <- parens (commaSep pExpr)
      semi
      return (Call name args)

-- IF         -> "if" EXPR "then" STMT+ MAYBE_ELSE "fi" 
-- MAYBE_ELSE -> "else" STMT+ | ε
pIf
  = do
      reserved "if"
      cond <- pExpr
      reserved "then"
      thenStmts <- many1 pStmt
      maybeElseStmts <- optionMaybe (reserved "else" >> many1 pStmt)
      reserved "fi"
      case maybeElseStmts of
        Nothing        -> return (If cond thenStmts)
        Just elseStmts -> return (IfElse cond thenStmts elseStmts)


-- WHILE      -> "while" EXPR "do" STMT+ "od"
pWhile
  = do
      reserved "while"
      cond <- pExpr
      reserved "do"
      stmts <- many1 pStmt
      reserved "od"
      return (While cond stmts)


{-

ZOOM a -> ε | "[" a "]" | "[" a "," a "]"


ZOOM_a  -> ε | "[" a "]" | "[" a "," a "]"
ZOOM_a  -> ε | "[" a ZOOM1_a
ZOOM1_a -> "," a "]" | "]"


X[4,5]----------------->
|
|
|
|
|
v

.-----------------------
|      |
|      v
|-->[X_3,2]
|
|
|
|

-}


-- SHAPED_ID  -> id EXPR_SHAPE
-- EXPR_SHAPE -> ε | "[" EXPR "]" | "[" EXPR "," EXPR "]"
pVar :: Parser Var
pVar
  = do
      name <- identifier
      subscript <- zoom pExpr
      case subscript of
        []    -> return Var0 name
        [i]   -> return Var1 name i
        [i,j] -> return Var2 name i j

zoom :: (Parser a) -> (Parser [a])
zoom parser
  = 
    do 
      maybe parse "[a" -NO-> return []
        |YES
        maybe parse ",b]" -NO-> return [a]
          |YES
          return [a,b]
          
  = option [] (brackets (zoom' parser))
zoom' parser -- parse 1 or 2 things inside those brackets
  = do
      a <- parser
      maybeB <- optionMaybe (comma >> parser)
      case maybeB of
        Nothing -> return [a]
        Just b  -> return [a, b]


-- DECL_SHAPE -> ε | "[" int "]" | "[" int "," int "]"
pDim :: Parser Dim
pDim
  = option Dim0 $ do
      ints <- brackets pDim'
      case ints of
        [n]   -> return (Dim1 n)
        [n,m] -> return (Dim2 n m)
pDim' :: Parser [Int]
pDim'
  = do
      n <- integer
      maybeM <- optionMaybe (comma >> integer)
      case maybeM of
        Nothing -> return [n]
        Just m  -> return [n, m]




-- assumes a function named `pExpr :: Parser Expr` is defined below

-- ----------------------------------------------------------------------------
-- Expression Parsing

