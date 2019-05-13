import Data.Either (isLeft)

import Test.HUnit

import Text.Parsec (parse, eof, ParseError)

import GoatLang.AST
import GoatLang.Parser
import GoatLang.PrettyPrint
import GoatLang.Token

-- A ParserUnitTest is a collection of test cases assocated with a single parser.
data ParserUnitTest node
  = ParserUnitTest (Parser node) [ParserTestCase node]

-- A ParserTestCase is an expected output corresponding to a list of inputs.
data ParserTestCase node
  = ParserTestCase (ParseResult node) [GoatInput]

-- A ParseResult corresponds to either a parsing error or an ASTNode.
data ParseResult node
  = ParseFailure
  | ParseSuccess node

type GoatInput = String

generateParserUnitTest :: (Eq node, Show node) => ParserUnitTest node -> Test
generateParserUnitTest (ParserUnitTest parser cases)
  = TestList (map (generateTestCase parser) cases)

generateTestCase :: (Eq node, Show node) => Parser node -> ParserTestCase node
  -> Test
generateTestCase parser (ParserTestCase result inputs)
  = TestList (map (generateAssertion parser result) inputs)

generateAssertion :: (Eq node, Show node) => Parser node -> ParseResult node
  -> GoatInput -> Test
generateAssertion parser result input
  = case result of
      ParseFailure -> TestCase $
        assertBool "" $ isLeft $ getParseResult parser input
      ParseSuccess node -> TestCase $ assertEqual "" (Right node) $
        getParseResult parser input

getParseResult :: Parser node -> GoatInput -> Either ParseError node
getParseResult parser input
  = parse (do {result <- parser; eof; return result}) "" input

--------------------------------------------------------------------------------

integerTest :: ParserUnitTest Int
integerTest
  = ParserUnitTest integer [
      ParserTestCase (ParseSuccess 42)
        ["42", "042", "0042", "00042"]
    , ParserTestCase (ParseSuccess 0)
        ["0", "00", "000"]
    , ParserTestCase (ParseSuccess 1234567890)
        ["01234567890"]
    , ParserTestCase ParseFailure
        ["", "4 2", "4,2", "0x42", "0xff", "4.2", "4."]
    ]

integerOrFloatTest :: ParserUnitTest (Either Int Float)
integerOrFloatTest
  = ParserUnitTest integerOrFloat [
      ParserTestCase (ParseSuccess $ Left 1234567890)
        ["01234567890"]
    , ParserTestCase (ParseSuccess $ Left 42)
        ["42", "042", "0042", "00042"]
    , ParserTestCase (ParseSuccess $ Left 0)
        ["0", "00", "000"]
    , ParserTestCase (ParseSuccess $ Right 12345.06789)
        ["12345.06789", "0012345.06789000"]
    , ParserTestCase (ParseSuccess $ Right 0.0)
        ["0.0", "00.00", "000.000"]
    , ParserTestCase ParseFailure
        [ "", "4 2", "4,2", "0x42", "0xff", ".0", "4.", "4.2.", "4.2.3"
        , "0.", "0. 0", "1e3", "1E3", "1E-3", "1E+4", "0x42"
        ]
    ]

stringLiteralTest :: ParserUnitTest String
stringLiteralTest
  = ParserUnitTest stringLiteral
    [ ParserTestCase (ParseSuccess "hello") ["\"hello\""]
    , ParserTestCase (ParseSuccess "hello\n") ["\"hello\\n\""]
    , ParserTestCase (ParseSuccess "hello\\t") ["\"hello\\t\""]
    , ParserTestCase (ParseSuccess "hello\\") ["\"hello\\\""]
    , ParserTestCase (ParseSuccess "hello\\world") ["\"hello\\world\""]
    , ParserTestCase ParseFailure
      ["\"hello\n\"", "\"hello\t\"", "\"hello", "hello\"", "\"hello\"\""]
    ]

pParamTest :: ParserUnitTest Param
pParamTest
  = ParserUnitTest pParam
    [ ParserTestCase (ParseSuccess $ Param Val BoolType (Id "a"))
      ["val bool a", "val  bool  a", "val\tbool\ta", "val\nbool\na"]
    , ParserTestCase ParseFailure
      [ "val val var", "val ref var", "ref val var", "ref ref var"
      , "bool val var", "bool ref var", "float val var", "float ref var"
      , "int val var", "int ref var  ", "VAL bool var", "REF bool var"
      , "Val bool var", "Ref bool var", "vAL bool var", "rEF bool var"
      , "bool bool var", "val' bool var", "ref' bool var", "val _ var"
      , "val bool _", "val _ _", "val bool true", "val bool \"hello\""
      , "val bool 42", "val bool 3.14"
      ]
    ]

pDimTest :: ParserUnitTest Dim
pDimTest
  = ParserUnitTest pDim
    [ ParserTestCase ParseFailure
      ["[]", "[][]", "[,]", "[ , ]", "[42][]", "[42,]", "[42, ]", "[][42]"
      , "[,42]", "[ ,42]", "[[]]", "[[]][[]]", "[[],[]]", "[][[]]", "[,[]]"
      , "[ ,[]]", "[[]][]", "[[],]", "[[], ]", "[[42]]", "[[42]][[42]]"
      , "[[42],[42]]", "[42][[42]]", "[42,[42]]", "[[42]][42]", "[[42],42]"
      , "[\"hello\"]", "[\"hello\"][\"harald\"]"
      , "[\"hello\",\"harald\"]", "[yarra][trams]", "[yarra,trams]"
      , "[\"COMP\"][90045]", "[\"COMP\",90045]", "[90045][\"COMP\"]"
      , "[90045,\"COMP\"]", "[1][2][3]", "[1,2,3]", "[3.14]", "[3.14][42]"
      , "[3.14,42]", "[42][3.14]", "[42,3.14]", "[3.14][2.72]", "[3.14,[2.72]"
      , "[42.]", "[.42]", "[42hello]", "[42_]", "[42+]"]

pExprTest :: ParserUnitTest Expr
pExprTest
  = ParserUnitTest pExpr
    [ ParserTestCase ParseFailure
      [ "+", "-", "*", "/", "=", ">", ">=", "<", "<=", "&&", "||", "!"
      , "1 2", "3.14 2.72", "1 +", "1 -", "1 *", "1 /", "1 =", "1 >", "1 >="
      , "1 <", "1 <=", "1 &&", "1 ||", "1 !", "true 2", "true false", "true +"
      , "true -", "true *", "true /", "true =", "true >", "true >=", "true <"
      , "true <=", "true &&", "true ||", "true !", "1 = 2 = 3", "1 < 2 < 3"
      , "1 < 2 = 3", "1 = 2 < 3", "1 <= 2 <= 3", "1 >= 2 >= 3", "1 + + 3"
      , "true && && false", "true || || false", "true || && false", "1 true"
      , "true 1"]
    ]

pAsgTest :: ParserUnitTest Stmt
pAsgTest
  = ParserUnitTest pAsg
    [ ParserTestCase ParseFailure
      [ "var = 1;", "var :=;", ":= 42;", "var := read;"
      , "foo < bar := true;", "var +:= 1;", "\"var\" := true;", "true := var;"
      , "[] := 42;", "[var] := 42;", "var[] := 42;", "var[][] := 42;"
      , "var[[0]] := 42;", "var := call factorial(n);", "var := factorial(n);"
      , "var := main();", "var := +;", "-var := 42;", "!var := false;"
      ]
    ]



writeFTest :: Display f => WriterUnitTest f
writeFTest
  = WriterUnitTest writeF
    [ WriterTestCase "" Dim0
    , WriterTestCase "[0]" (Dim1 0)
    , WriterTestCase "[1]" (Dim1 1)
    , WriterTestCase "[1, 0]" (Dim2 1 0)
    , WriterTestCase "[10, 20]" (Dim2 10 20)
    , WriterTestCase "[1, 0]" (Dim2 1 0)
    , WriterTestCase "[10, 20]" (Dim2 10 20)
    , WriterTestCase "val bool a" (Param Val BoolType "a")
    , WriterTestCase "ref bool alt" (Param Ref BoolType "alt")
    , WriterTestCase "val int bc'" (Param Val IntType "bc'")
    , WriterTestCase "ref float ___aleph" (Param Ref FloatType "___aleph")
    ]

writeDeclWithTest :: WriterUnitTest Decl
writeDeclWithTest
  = WriterUnitTestCase (writeDeclWith $ return ()) -- no indentation
    [ WriterTestCase "bool i[1, 2];\n"  (Decl BoolType "i" (Dim2 1 2))
    , WriterTestCase "int action[1];\n" (Decl IntType "action" (Dim1 1))
    , WriterTestCase "float boolean;\n" (Decl FloatType "boolean" (Dim0))
    ]

writeVarTest :: WriterUnitTest Var
writeVarTest
  = WriterUnitTestCase writeVar
    [ WriterTestCase "x" (Var0 "x")
    , WriterTestCase "x[1]" (Var1 "x" (IntConst 1))
    , WriterTestCase "x[2, 3.0]" (Var2 "x" (IntConst 2) (FloatConst 3.0))
    ]

writeStmtWithTest :: WriterUnitTest Stmt
writeStmtWithTest
  = WriterUnitTestCase (writeStmtWith $ return ()) -- no indentation
    [ WriterTestCase "call f();\n" (Call "f" [])
    , WriterTestCase "call f(1);\n" (Call "f" [IntConst 1])
    , WriterTestCase "call f(1, 2);\n" (Call "f" [IntConst 1, IntConst 2])
    , WriterTestCase "x := 42;\n" (Asg (Var0 "x") (IntConst 42))
    , WriterTestCase "x[1] := 42;\n" (Asg (Var1 "x" (IntConst 1)) (IntConst 42))
    , WriterTestCase "x[1, 2] := 42;\n" (Asg (Var2 "x" (IntConst 1) (IntConst 2)) (IntConst 42))
    , WriterTestCase "read x;\n" (Read (Var0 "x"))
    , WriterTestCase "read x[1];\n" (Read (Var1 "x" (IntConst 1)))
    , WriterTestCase "read x[1, 2];\n" (Read (Var2 "x" (IntConst 1) (IntConst 2)))
    , WriterTestCase "write x;\n" (Write $ VarExpr (Var0 "x"))
    , WriterTestCase "write x[1];\n" (Write $ VarExpr (Var1 "x" (IntConst 1)))
    , WriterTestCase "write x[1, 2];\n" (Write $ VarExpr (Var2 "x" (IntConst 1) (IntConst 2)))
    -- TODO: Test compound statement writing
    ]

writeExprTest :: WriterUnitTest Expr
writeExprTest
  = WriterUnitTestCase writeExpr
    [ WriterTestCase "\"hello, world!\\n\"" (StrConst "hello, world!\n")
    -- TODO: Test expression writing
    ]

main
  = runTestTT $ TestList [
      generateParserUnitTest integerTest
    , generateParserUnitTest integerOrFloatTest
    , generateParserUnitTest stringLiteralTest
    , generateParserUnitTest pParamTest
    , generateParserUnitTest pDimTest
    , generateParserUnitTest pExprTest
    , generateParserUnitTest pAsgTest

    , generateWriterUnitTest writeFTest
    , generateWriterUnitTest writeDeclWithTest
    , generateWriterUnitTest writeVarTest
    , generateWriterUnitTest writeStmtWithTest
    , generateWriterUnitTest writeExprTest
    ]