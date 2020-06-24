{-# LANGUAGE GADTs #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RecordWildCards #-}

module Data.Morpheus.Validation.Query.Arguments
  ( validateDirectiveArguments,
    validateFieldArguments,
  )
where

import Data.Foldable (traverse_)
import Data.Morpheus.Internal.Utils
  ( empty,
  )
import Data.Morpheus.Types.Internal.AST
  ( Argument (..),
    ArgumentDefinition,
    Arguments,
    ArgumentsDefinition (..),
    DirectiveDefinition,
    DirectiveDefinition (..),
    FieldDefinition (..),
    OUT,
    ObjectEntry (..),
    RAW,
    RESOLVED,
    RawValue,
    ResolvedValue,
    TypeRef (..),
    VALID,
    Value (..),
    fieldContentArgs,
  )
import Data.Morpheus.Types.Internal.Validation
  ( InputSource (..),
    Scope (..),
    SelectionValidator,
    askInputFieldType,
    askVariables,
    asks,
    selectKnown,
    selectRequired,
    selectWithDefaultValue,
    startInput,
    withPosition,
  )
import Data.Morpheus.Validation.Internal.Value
  ( validateInput,
  )

-- only Resolves , doesnot checks the types
resolveObject :: RawValue -> SelectionValidator ResolvedValue
resolveObject = resolve
  where
    resolveEntry :: ObjectEntry RAW -> SelectionValidator (ObjectEntry RESOLVED)
    resolveEntry (ObjectEntry name v) = ObjectEntry name <$> resolve v
    ------------------------------------------------
    resolve :: RawValue -> SelectionValidator ResolvedValue
    resolve Null = pure Null
    resolve (Scalar x) = pure $ Scalar x
    resolve (Enum x) = pure $ Enum x
    resolve (List x) = List <$> traverse resolve x
    resolve (Object obj) = Object <$> traverse resolveEntry obj
    resolve (VariableValue ref) =
      askVariables
        >>= fmap (ResolvedVariable ref)
          . selectRequired ref

resolveArgumentVariables ::
  Arguments RAW ->
  SelectionValidator (Arguments RESOLVED)
resolveArgumentVariables =
  traverse resolveVariable
  where
    resolveVariable :: Argument RAW -> SelectionValidator (Argument RESOLVED)
    resolveVariable (Argument key val position) = do
      constValue <- resolveObject val
      pure $ Argument key constValue position

validateArgument ::
  Arguments RESOLVED ->
  ArgumentDefinition ->
  SelectionValidator (Argument VALID)
validateArgument
  requestArgs
  argumentDef@FieldDefinition
    { fieldName,
      fieldType = TypeRef {typeWrappers}
    } =
    do
      argumentPosition <- asks position
      argument <-
        selectWithDefaultValue
          (\argumentValue -> Argument {argumentName = fieldName, argumentValue, argumentPosition})
          argumentDef
          requestArgs
      validateArgumentValue argument
    where
      -------------------------------------------------------------------------
      validateArgumentValue :: Argument RESOLVED -> SelectionValidator (Argument VALID)
      validateArgumentValue arg@Argument {argumentValue = value, ..} =
        withPosition argumentPosition
          $ startInput (SourceArgument arg)
          $ do
            datatype <- askInputFieldType argumentDef
            argumentValue <-
              validateInput
                typeWrappers
                datatype
                (ObjectEntry fieldName value)
            pure Argument {argumentValue, ..}

validateFieldArguments ::
  FieldDefinition OUT ->
  Arguments RAW ->
  SelectionValidator (Arguments VALID)
validateFieldArguments fieldDef@FieldDefinition {fieldContent} =
  validateArgumengts (`selectKnown` fieldDef) argsDef
  where
    argsDef = maybe empty fieldContentArgs fieldContent

-------------------------------------------------

validateDirectiveArguments ::
  DirectiveDefinition ->
  Arguments RAW ->
  SelectionValidator (Arguments VALID)
validateDirectiveArguments
  directiveDef@DirectiveDefinition
    { directiveDefinitionArgs
    } =
    validateArgumengts
      (`selectKnown` directiveDef)
      directiveDefinitionArgs

validateArgumengts ::
  (Argument RESOLVED -> SelectionValidator ArgumentDefinition) ->
  ArgumentsDefinition ->
  Arguments RAW ->
  SelectionValidator (Arguments VALID)
validateArgumengts checkUnknown argsDef rawArgs =
  do
    args <- resolveArgumentVariables rawArgs
    traverse_ checkUnknown args
    traverse (validateArgument args) (arguments argsDef)
