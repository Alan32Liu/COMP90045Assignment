module GoatLang.CodeGen where

-- ----------------------------------------------------------------------------
--    COMP90045 Programming Language Implementation, Assignment Stage 1
--
--                      GOAT - Oz Code Generator
--
-- Well-chosen team name:              pli-dream-team-twentee-nineteen
-- Well-chosen team members:
-- * Alan Ung                          alanu
-- * David Stern                       dibstern
-- * Dongge Liu                        donggel
-- * Mariam Shahid                     mariams
-- * Matthew Farrugia-Roberts          farrugiam
--
-- ----------------------------------------------------------------------------

import Control.Monad (mapM_, when)
import Control.Monad.State

import Util.DiffList

import GoatLang.AST
import GoatLang.OzCode
import GoatLang.SymbolTable
import GoatLang.PrettyPrint


-- Summary of TODO items from throughout file:
--
-- Milestone 4:
-- - Allow multiple procedures in genCodeGoatProgram
-- - Extend genCodeGoatProc to allow procedures not named "main"
-- - Extend genCodeGoatProc to allow for non-empty list of parameters (by val)
-- - Extend genCodeStmt to allow Call statements (with value arguments only)
--
-- Milestone 5:
--
-- - Add to the milestone 4 stuff the ability to handle reference parameters in
--   all possible places.
--
-- Milestone 6:
--
-- - Allow for arrays and matrices.
--
-- When we do semantic analysis:
--
-- - genCodeExprInto assumes that all expressions are completely well-types
--   Semantic analysis will need to come in and actually provide that guarantee.
--
-- - Of course, we will want to change from using a recursive function to
--   calculate expression types to precomputing these types during semantic
--   analysis and embedding them within the Expression AST nodes themselves.
--
-- - Idea: Annotate the AST with additional 'float cast' nodes to avoid having
--   a separate case for every operation when the arguments might be an int and
--   a float. E.g. an annotated AST requiring a cast, such as for the expression
--   `4 + 0.2`, could look as follows:
--   ```
--   Add FloatType
--     (FloatCast (IntConst 4))
--     (FloatConst 0.2)
--   ```


-- ----------------------------------------------------------------------------
-- CodeGen State Monad
-- ----------------------------------------------------------------------------

-- We'll use a state monad to simplify construction of Oz programs
type CodeGen a
  = State CodeGenState a

-- The state monad will store a label counter (an int) and a (difference) list
-- of OzLines (instructions or peudo-instructions; see OzCode module).
data CodeGenState
  = CodeGenState LabelCounter (DiffList OzLine)

type LabelCounter
  = Int


-- genCode
-- Top level function: use the code generators defined below to convert a Goat
-- Program (an AST) into an Oz Program (a list of Oz lines).
genCode :: GoatProgram -> OzProgram
genCode goatProgram
  = ozProgram
  where
    -- start with label counter at 0 and an empty list of program lines
    start = CodeGenState 0 (mempty :: DiffList OzLine)

    -- run the code generators an extract the completed difference list of lines
    ((), CodeGenState _ lines) = runState (genCodeGoatProgram goatProgram) start

    -- convert the result into an Oz program
    ozProgram = OzProgram (listify lines)



-- Internal helper functions for interacting directly with the CodeGen state:

-- getLabelCounter
-- Extract the label counter from the monad's state and return.
getLabelCounter :: CodeGen LabelCounter
getLabelCounter
  = do
      CodeGenState labelCounter _ <- get
      return labelCounter

-- incLabelCounter
-- Add 1 to the label counter in the monad's state.
incLabelCounter :: CodeGen ()
incLabelCounter
  = do
      CodeGenState labelCounter instrs <- get
      put $ CodeGenState (labelCounter + 1) instrs

-- appendLine
-- Append a new oz line to the monad's (difference) list of oz lines
-- (conceptually adding it to the end of the program-so-far).
appendLine :: OzLine -> CodeGen ()
appendLine line
  = do
      CodeGenState labelCounter lines <- get
      put $ CodeGenState labelCounter (lines `snoc` line)
      -- NOTE: snoc is 'backwards cons': append a single thing to a diff list


-- External helper functions for indirectly using the CodeGen state:

-- getNewBlockLabel
-- Increment the internal label counter and return a fresh block label.
getNewBlockLabel :: CodeGen Label
getNewBlockLabel
  = do
      labelCounter <- getLabelCounter
      incLabelCounter
      return (BlockLabel labelCounter)

-- instr
-- Append an Instruction to the program's lines.
instr :: Instruction -> CodeGen ()
instr instruction
  = appendLine $ Instr instruction

-- label
-- Append a Label to the program's lines (as a pseudo-instruction).
label :: Label -> CodeGen ()
label lab
  = appendLine $ Label lab

-- comment
-- Append a Comment to the program's lines (as a pseudo-instruction).
comment :: String -> CodeGen ()
comment text
  = appendLine $ Comment text




-- ----------------------------------------------------------------------------
-- Code generators
-- ----------------------------------------------------------------------------

-- genCodeGoatProgram
-- Action to generate instructions for a full Goat Program.
genCodeGoatProgram :: GoatProgram -> CodeGen ()
-- TODO: allow multiple procedures (we'll just need to `mapM_ genCodeProc`)
genCodeGoatProgram (GoatProgram [main])
  = do
      instr $ CallInstr (ProcLabel "main")
      instr $ HaltInstr
      genCodeProc main


-- genCodeProc
-- Action to generate instructions for a single Goat Procedure, including
-- the procedure's prologue and epilogue.
genCodeProc :: Proc -> CodeGen ()
-- TODO: allow declarations in main
-- TODO: allow procedures not named "main"
-- TODO: allow non-empty list of parameters
genCodeProc (Proc (Id "main") [] decls stmts)
  = do
      let varSymTable = constructVarSymTable [] decls
      label $ ProcLabel "main"
      comment "prologue"
      -- TODO: figure out TRUE required frame size (incl. arrays, matrices)
      instr $ PushStackFrameInstr (FrameSize $ numSlots varSymTable)
      -- TODO: copy any parameters from registers to appropriate stack slots
      mapM_ (genCodeInitVar varSymTable) decls
      comment "procedure body"
      mapM_ (genCodeStmt varSymTable) stmts
      comment "epilogue"
      instr $ PopStackFrameInstr (FrameSize $ numSlots varSymTable)
      instr ReturnInstr

-- genCodeInitVar
-- Action to generate code to initialise a local variable to 0.
-- TODO: Add suport for local array and matrix variables.
genCodeInitVar :: VarSymTable -> Decl -> CodeGen ()
genCodeInitVar symTable decl@(Decl baseType ident Dim0)
  = do
      comment $ "initialising " ++ (init $ prettify decl)
      let slot = varStackSlot $ lookupVarRecord symTable ident
      case baseType of
        FloatType -> instr $ RealConstInstr (Reg 0) 0.0
        otherwise -> instr $ IntConstInstr (Reg 0) 0
      instr $ StoreInstr slot (Reg 0)


-- genCodeStmt
-- Action to generate code for a single Goat Statement (may be an atomic or
-- composite statement).
-- TODO: add Call statements
genCodeStmt :: VarSymTable -> Stmt -> CodeGen ()

genCodeStmt varSymTable stmt@(WriteExpr expr)
  = do
      comment $ init $ prettify stmt
      genCodeExprInto varSymTable (Reg 0) expr
      case getExprType varSymTable expr of
        BoolType -> instr $ CallBuiltinInstr PrintBool
        IntType -> instr $ CallBuiltinInstr PrintInt
        FloatType -> instr $ CallBuiltinInstr PrintReal

genCodeStmt _ stmt@(WriteString str)
  = do
      comment $ init $ prettify stmt
      instr $ StringConstInstr (Reg 0) str
      instr $ CallBuiltinInstr PrintStr

-- TODO: handle reading into arrays/matrices
genCodeStmt varSymTable stmt@(Read (Single ident))
  = do
      let record = lookupVarRecord varSymTable ident
      comment $ init $ prettify stmt
      case varType record of
        BoolType -> instr $ CallBuiltinInstr ReadBool
        IntType -> instr $ CallBuiltinInstr ReadInt
        FloatType -> instr $ CallBuiltinInstr ReadReal
      instr $ StoreInstr (varStackSlot record) (Reg 0)

-- TODO: handle assigning into arrays/matrices
genCodeStmt varSymTable stmt@(Asg (Single ident) expr)
  = do
      comment $ init $ prettify stmt
      genCodeExprInto varSymTable (Reg 0) expr
      let record = lookupVarRecord varSymTable ident
      when (varType record == FloatType) $
        realify (Reg 0) (getExprType varSymTable expr)
      instr $ StoreInstr (varStackSlot record) (Reg 0)

genCodeStmt varSymTable (If cond thenStmts)
  = do
      comment $ "if " ++ prettify cond
      genCodeExprInto varSymTable (Reg 0) cond
      fiLabel <- getNewBlockLabel
      instr $ BranchOnFalseInstr (Reg 0) fiLabel
      mapM_ (genCodeStmt varSymTable) thenStmts
      label $ fiLabel

genCodeStmt varSymTable (IfElse cond thenStmts elseStmts)
  = do
      comment $ "if-else " ++ prettify cond
      genCodeExprInto varSymTable (Reg 0) cond
      elseLabel <- getNewBlockLabel
      instr $ BranchOnFalseInstr (Reg 0) elseLabel
      mapM_ (genCodeStmt varSymTable) thenStmts
      fiLabel <- getNewBlockLabel
      instr $ BranchUncondInstr fiLabel
      label $ elseLabel
      mapM_ (genCodeStmt varSymTable) elseStmts
      label $ fiLabel

genCodeStmt varSymTable (While cond stmts)
  = do
      comment $ "while " ++ prettify cond
      whileLabel <- getNewBlockLabel
      label $ whileLabel
      genCodeExprInto varSymTable (Reg 0) cond
      odLabel <- getNewBlockLabel
      instr $ BranchOnFalseInstr (Reg 0) odLabel
      mapM_ (genCodeStmt varSymTable) stmts
      label $ odLabel


-- genCodeExprInto register
-- Action to generate code that will get the result of an expression into this
-- register.
genCodeExprInto :: VarSymTable -> Reg -> Expr -> CodeGen ()
-- TODO: implement code generation for ScalarExprs (must treat value and ref
-- variables correctly for Singular variables, and must handle indexing into
-- Array and Matrix variables).
-- TODO: The following code assumes that the expression is well-typed. Semantic
-- analysis will need to come in and actually provide that guarantee at some
-- point.

-- Base cases: float, int and bool constants:

genCodeExprInto _ register (IntConst int)
  = instr $ IntConstInstr register int

genCodeExprInto _ register (FloatConst float)
  = instr $ RealConstInstr register float

-- In Oz we represent True as the integer 1, and false as the integer 0
genCodeExprInto _ register (BoolConst True)
  = instr $ IntConstInstr register 1
genCodeExprInto _ register (BoolConst False)
  = instr $ IntConstInstr register 0

-- Recursive cases: binary and unary operations involving nested expressions:

-- First, treat the non-strict operations specially:

-- 'And' will not actually use oz's 'and' instruction (which is strict).
-- Instead, we'll:
-- 1. Load the first operand into the target register.
-- 2. If false (0), we are done! Skip evaluating the second operand, and leave
--    the 0 in the target register.
-- 3. If true (1), we need to check the second operand. Load into target
--    register.
-- 4. Whatever the result, leave it in the target register (it's the result of
--    the And operation).
genCodeExprInto varSymTable register (BinExpr And l r)
  = do
      afterLabel <- getNewBlockLabel
      genCodeExprInto varSymTable register l
      instr $ BranchOnFalseInstr register afterLabel
      genCodeExprInto varSymTable register r
      label afterLabel

-- Or is similar (but we skip the second operand when the first is True,
-- rather than False):
genCodeExprInto varSymTable register (BinExpr Or l r)
  = do
      afterLabel <- getNewBlockLabel
      genCodeExprInto varSymTable register l
      instr $ BranchOnTrueInstr register afterLabel
      genCodeExprInto varSymTable register r
      label afterLabel

-- All other expressions are strict, so we can safely load the operands into
-- two registers then just perform the appropriate operation:
genCodeExprInto varSymTable register (BinExpr op lExpr rExpr)
  = do
      genCodeExprInto varSymTable register lExpr
      genCodeExprInto varSymTable (succ register) rExpr
      genCodeBinOp register register (succ register) op lType rType
  where
    lType = getExprType varSymTable lExpr
    rType = getExprType varSymTable rExpr

-- There are only two cases for unary operations:
-- Logical `Not`:
genCodeExprInto varSymTable register (UnExpr Not expr)
  = do
      genCodeExprInto varSymTable register expr
      instr $ NotInstr register register

-- And arithmetic `Neg` (which could be applied to either a real value or an
-- int value):
genCodeExprInto varSymTable register (UnExpr Neg expr)
  = do
      genCodeExprInto varSymTable register expr
      instr $ instruction register register
  where
    instruction = case getExprType varSymTable expr of
      FloatType -> NegRealInstr
      IntType -> NegIntInstr

-- TODO: handle arrays/matrices
genCodeExprInto varSymTable register (ScalarExpr (Single ident))
  = do
      let slot = varStackSlot $ lookupVarRecord varSymTable ident
      instr $ LoadInstr register slot


-- genCodeBinOp
-- Action to generate code for an arbitrary binary operation from two registers
-- into a third destination register, given the known types of the values in the
-- two
genCodeBinOp :: Reg -> Reg -> Reg -> BinOp -> BaseType -> BaseType -> CodeGen ()

-- If both
genCodeBinOp destReg lReg rReg op IntType IntType
  = instr $ (lookupOpInt op) destReg lReg rReg

genCodeBinOp destReg lReg rReg op BoolType BoolType
  = instr $ (lookupOpBool op) destReg lReg rReg

genCodeBinOp destReg lReg rReg op FloatType FloatType
  = instr $ (lookupOpReal op) destReg lReg rReg

-- Finally, maybe we have one int value and one real value:
genCodeBinOp destReg lReg rReg op lType rType
  = do
      -- ensure both arguments are formatted as reals
      realify lReg lType
      realify rReg rType
      instr $ (lookupOpIntOrReal op) destReg lReg rReg

-- realify
-- Action to generate code to cast an integer value to a real, if necessary
-- (this is a noop if the BaseType is FloatType).
realify :: Reg -> BaseType -> CodeGen ()
realify _ FloatType
  = return ()
realify register IntType
  = instr $ IntToRealInstr register register
-- TODO (semantic analysis):
-- Annotate the AST with additional 'float cast' nodes to avoid the need for
-- this case. E.g. an annotated AST requiring a cast, such as for the
-- expression `4 + 0.2`, could look like this:
-- ```
-- Add FloatType
--   (FloatCast (IntConst 4))
--   (FloatConst 0.2)
-- ```
--
-- Then all we'd need would be:
--
-- ```
-- genCodeExprInto register (FloatCase expr)
--   = do
--       genCodeExprInto register expr
--       instr $ IntToRealInstr register register
-- ```


-- Look up the appropriate Oz Instruction for two real arguments:
-- (arithmetic and comparisons are allowed)
lookupOpReal :: BinOp -> (Reg -> Reg -> Reg -> Instruction)
lookupOpReal Add
  = AddRealInstr
lookupOpReal Sub
  = SubRealInstr
lookupOpReal Mul
  = MulRealInstr
lookupOpReal Div
  = DivRealInstr
lookupOpReal Equ
  = EquRealInstr
lookupOpReal NEq
  = NEqRealInstr
lookupOpReal LTh
  = LThRealInstr
lookupOpReal LEq
  = LEqRealInstr
lookupOpReal GTh
  = GThRealInstr
lookupOpReal GEq
  = GEqRealInstr

-- Look up the appropriate Oz Instruction for an int and a real argument
-- (NOTE: Equ and NEq are not allowed!)
lookupOpIntOrReal :: BinOp -> (Reg -> Reg -> Reg -> Instruction)
lookupOpIntOrReal Add
  = AddRealInstr
lookupOpIntOrReal Sub
  = SubRealInstr
lookupOpIntOrReal Mul
  = MulRealInstr
lookupOpIntOrReal Div
  = DivRealInstr
lookupOpIntOrReal LTh
  = LThRealInstr
lookupOpIntOrReal LEq
  = LEqRealInstr
lookupOpIntOrReal GTh
  = GThRealInstr
lookupOpIntOrReal GEq
  = GEqRealInstr

-- Look up the appropriate Oz Instruction for two int arguments (arithmetic
-- and comparisons are allowed)
lookupOpInt :: BinOp -> (Reg -> Reg -> Reg -> Instruction)
lookupOpInt Add
  = AddIntInstr
lookupOpInt Sub
  = SubIntInstr
lookupOpInt Mul
  = MulIntInstr
lookupOpInt Div
  = DivIntInstr
lookupOpInt Equ
  = EquIntInstr
lookupOpInt NEq
  = NEqIntInstr
lookupOpInt LTh
  = LThIntInstr
lookupOpInt LEq
  = LEqIntInstr
lookupOpInt GTh
  = GThIntInstr
lookupOpInt GEq
  = GEqIntInstr

-- Look up the appropriate value for two boolean arguments (only comparisons
-- are allowed)
lookupOpBool :: BinOp -> (Reg -> Reg -> Reg -> Instruction)
lookupOpBool Equ
  = EquIntInstr
lookupOpBool NEq
  = NEqIntInstr
lookupOpBool LTh
  = LThIntInstr
lookupOpBool LEq
  = LEqIntInstr
lookupOpBool GTh
  = GThIntInstr
lookupOpBool GEq
  = GEqIntInstr

-- Recursively (re-)compute the type of
-- TODO: Of course, we will want to change from using a recursive function to
-- calculate expression types to precomputing these types during semantic
-- analysis and embedding them within the Expression AST nodes themselves.
getExprType :: VarSymTable -> Expr -> BaseType
getExprType _ (BoolConst _)
  = BoolType
getExprType _ (FloatConst _)
  = FloatType
getExprType _ (IntConst _)
  = IntType
getExprType varSymTable (BinExpr operator left right)
  = case operator of
      Add -> case getExprType varSymTable left of
        FloatType -> FloatType
        otherwise -> case getExprType varSymTable right of
          FloatType -> FloatType
          otherwise -> IntType
      Sub -> case getExprType varSymTable left of
        FloatType -> FloatType
        otherwise -> case getExprType varSymTable right of
          FloatType -> FloatType
          otherwise -> IntType
      Mul -> case getExprType varSymTable left of
        FloatType -> FloatType
        otherwise -> case getExprType varSymTable right of
          FloatType -> FloatType
          otherwise -> IntType
      Div -> case getExprType varSymTable left of
        FloatType -> FloatType
        otherwise -> case getExprType varSymTable right of
          FloatType -> FloatType
          otherwise -> IntType
      otherwise -> BoolType
getExprType varSymTable (UnExpr operator operand)
  = getExprType varSymTable operand
getExprType varSymTable (ScalarExpr scalar)
  = getScalarType varSymTable scalar

getScalarType :: VarSymTable -> Scalar -> BaseType
getScalarType varSymTable (Single ident)
  = varType $ lookupVarRecord varSymTable ident
getScalarType varSymTable (Array ident iExpr)
  = varType $ lookupVarRecord varSymTable ident
getScalarType varSymTable (Matrix ident iExpr jExpr)
  = varType $ lookupVarRecord varSymTable ident
