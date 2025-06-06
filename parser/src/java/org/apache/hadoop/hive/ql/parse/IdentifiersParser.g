/**
   Licensed to the Apache Software Foundation (ASF) under one or more 
   contributor license agreements.  See the NOTICE file distributed with 
   this work for additional information regarding copyright ownership.
   The ASF licenses this file to You under the Apache License, Version 2.0
   (the "License"); you may not use this file except in compliance with 
   the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
parser grammar IdentifiersParser;

options
{
output=AST;
ASTLabelType=ASTNode;
backtrack=false;
k=3;
}

@members {
  @Override
  public Object recoverFromMismatchedSet(IntStream input,
      RecognitionException re, BitSet follow) throws RecognitionException {
    throw re;
  }
  @Override
  public void displayRecognitionError(String[] tokenNames,
      RecognitionException e) {
    gParent.errors.add(new ParseError(gParent, e, tokenNames));
  }

  int parameterIdx = 0;
  public int getParameterIdx() { return ++parameterIdx;}

  private int columnAliasCounter = 1;
  private void incAliasCounter() {
    ++columnAliasCounter;
  }

  private String generateColumnAlias() {
    return generateColumnAlias(columnAliasCounter);
  }

  private String generateColumnAlias(int index) {
    return "col" + index;
  }

  private void resetAliasCounter() {
    columnAliasCounter = 1;
  }
}

@rulecatch {
catch (RecognitionException e) {
  throw e;
}
}

//-----------------------------------------------------------------------------------

// group by a,b
groupByClause
@init { gParent.pushMsg("group by clause", state); }
@after { gParent.popMsg(state); }
    :
    KW_GROUP KW_BY groupby_expression
    -> groupby_expression
    ;

// support for new and old rollup/cube syntax
groupby_expression :
 rollupStandard |
 rollupOldSyntax|
 groupByEmpty
;

groupByEmpty
    :
    LPAREN RPAREN
    ;

// standard rollup syntax
rollupStandard
@init { gParent.pushMsg("standard rollup syntax", state); }
@after { gParent.popMsg(state); }
    :
    (rollup=KW_ROLLUP | cube=KW_CUBE)
    LPAREN expression ( COMMA expression)* RPAREN
    -> {rollup != null}? ^(TOK_ROLLUP_GROUPBY expression+)
    -> ^(TOK_CUBE_GROUPBY expression+)
    ;

// old hive rollup syntax
rollupOldSyntax
@init { gParent.pushMsg("rollup old syntax", state); }
@after { gParent.popMsg(state); }
    :
    expr=expressionsNotInParenthesis[false, false]
    ((rollup=KW_WITH KW_ROLLUP) | (cube=KW_WITH KW_CUBE)) ?
    (sets=KW_GROUPING KW_SETS
    LPAREN groupingSetExpression ( COMMA groupingSetExpression)*  RPAREN ) ?
    -> {rollup != null}? ^(TOK_ROLLUP_GROUPBY {$expr.tree})
    -> {cube != null}? ^(TOK_CUBE_GROUPBY {$expr.tree})
    -> {sets != null}? ^(TOK_GROUPING_SETS {$expr.tree} groupingSetExpression+)
    -> ^(TOK_GROUPBY {$expr.tree})
    ;


groupingSetExpression
@init {gParent.pushMsg("grouping set expression", state); }
@after {gParent.popMsg(state); }
   :
   (groupingSetExpressionMultiple) => groupingSetExpressionMultiple 
   |
   groupingExpressionSingle
   ;

groupingSetExpressionMultiple
@init {gParent.pushMsg("grouping set part expression", state); }
@after {gParent.popMsg(state); }
   :
   LPAREN 
   expression? (COMMA expression)*
   RPAREN
   -> ^(TOK_GROUPING_SETS_EXPRESSION expression*)
   ;

groupingExpressionSingle
@init { gParent.pushMsg("groupingExpression expression", state); }
@after { gParent.popMsg(state); }
    :
    expression -> ^(TOK_GROUPING_SETS_EXPRESSION expression)
    ;

havingClause
@init { gParent.pushMsg("having clause", state); }
@after { gParent.popMsg(state); }
    :
    KW_HAVING havingCondition -> ^(TOK_HAVING havingCondition)
    ;

qualifyClause
@init { gParent.pushMsg("qualify clause", state); }
@after { gParent.popMsg(state); }
    :
    KW_QUALIFY expression -> ^(TOK_QUALIFY expression)
    ;

havingCondition
@init { gParent.pushMsg("having condition", state); }
@after { gParent.popMsg(state); }
    :
    expression
    ;

expressionsInParenthesis[boolean isStruct, boolean forceStruct]
    :
    LPAREN! expressionsNotInParenthesis[isStruct, forceStruct] RPAREN!
    ;

expressionsNotInParenthesis[boolean isStruct, boolean forceStruct]
    :
    first=expressionOrDefault more=expressionPart[$expressionOrDefault.tree, isStruct]?
    -> {forceStruct && more==null}?
       ^(TOK_FUNCTION Identifier["struct"] {$first.tree})
    -> {more==null}?
       {$first.tree}
    -> {$more.tree}
    ;

expressionPart[CommonTree firstExprTree, boolean isStruct]
    :
    (COMMA expressionOrDefault)+
    -> {isStruct}? ^(TOK_FUNCTION Identifier["struct"] {$firstExprTree} expressionOrDefault+)
    -> {$firstExprTree} expressionOrDefault+
    ;

expressionOrDefault
    :
    (KW_DEFAULT ~DOT) => defaultValue
    | expression
    ;

// Parses comma separated list of expressions with optionally specified aliases.
// <expression> [<alias>] [, <expression> [<alias>]]
firstExpressionsWithAlias
@after { resetAliasCounter(); }
    :
    first=expression KW_AS? colAlias=identifier? (COMMA expressionWithAlias)* { incAliasCounter(); }
    -> {colAlias != null}? ^(TOK_FUNCTION Identifier["struct"] {$first.tree} ^(TOK_ALIAS identifier?) expressionWithAlias*)
    -> ^(TOK_FUNCTION Identifier["struct"] {$first.tree} ^(TOK_ALIAS { adaptor.create(Identifier, generateColumnAlias(1)) }) expressionWithAlias*)
    ;

// Parses expressions which may have alias.
// If alias is not specified generate one.
expressionWithAlias
    :
    expression KW_AS? alias=identifier? { incAliasCounter(); }
    -> { alias != null }? expression ^(TOK_ALIAS identifier?)
    -> expression ^(TOK_ALIAS { adaptor.create(Identifier, generateColumnAlias()) })
    ;

expressions
    :
    (expressionsInParenthesis[false, false]) => expressionsInParenthesis[false, false]
    |
    expressionsNotInParenthesis[false, false]
    ;

columnRefOrderInParenthesis
    :
    LPAREN columnRefOrder (COMMA columnRefOrder)* RPAREN -> columnRefOrder+
    ;

columnRefOrderNotInParenthesis
    :
    columnRefOrder (COMMA columnRefOrder)* -> columnRefOrder+
    ;
    
// order by a,b
orderByClause
@init { gParent.pushMsg("order by clause", state); }
@after { gParent.popMsg(state); }
    :
    KW_ORDER KW_BY columnRefOrder ( COMMA columnRefOrder)* -> ^(TOK_ORDERBY columnRefOrder+)
    ;
    
clusterByClause
@init { gParent.pushMsg("cluster by clause", state); }
@after { gParent.popMsg(state); }
    :
    KW_CLUSTER KW_BY expressions -> ^(TOK_CLUSTERBY expressions)
    ;

partitionByClause
@init  { gParent.pushMsg("partition by clause", state); }
@after { gParent.popMsg(state); }
    :
    KW_PARTITION KW_BY expressions -> ^(TOK_DISTRIBUTEBY expressions) 
    ;

distributeByClause
@init { gParent.pushMsg("distribute by clause", state); }
@after { gParent.popMsg(state); }
    :
    KW_DISTRIBUTE KW_BY expressions -> ^(TOK_DISTRIBUTEBY expressions) 
    ;

sortByClause
@init { gParent.pushMsg("sort by clause", state); }
@after { gParent.popMsg(state); }
    :
    KW_SORT KW_BY
    (
    (LPAREN) => columnRefOrderInParenthesis -> ^(TOK_SORTBY columnRefOrderInParenthesis)
    |
    columnRefOrderNotInParenthesis -> ^(TOK_SORTBY columnRefOrderNotInParenthesis)
    )
    ;

// TRIM([LEADING|TRAILING|BOTH] trim_characters FROM str)
trimFunction
    :
    KW_TRIM LPAREN (leading=KW_LEADING | trailing=KW_TRAILING | KW_BOTH)? (trim_characters=selectExpression)? KW_FROM (str=selectExpression) RPAREN
    -> {$leading != null}? ^(TOK_FUNCTION {adaptor.create(Identifier, "ltrim")} $str $trim_characters?)
    -> {$trailing != null}? ^(TOK_FUNCTION {adaptor.create(Identifier, "rtrim")} $str $trim_characters?)
    -> ^(TOK_FUNCTION {adaptor.create(Identifier, "trim")} $str $trim_characters?)
    ;

// fun(par1, par2, par3)
function
@init { gParent.pushMsg("function specification", state); }
@after { gParent.popMsg(state); }
    :
    (trimFunction) => (trimFunction)
    |
    functionName
    LPAREN
      (
        (STAR) => (star=STAR)
        | (dist=KW_DISTINCT | KW_ALL)? (selectExpression (COMMA selectExpression)*)?
      )
      (
        // SELECT rank(3) WITHIN GROUP (<order by clause>)
        (RPAREN KW_WITHIN) => (RPAREN (within=KW_WITHIN KW_GROUP LPAREN ordBy=orderByClause RPAREN))
        // No null treatment: SELECT first_value(b) OVER (<window spec>)
        // Standard null treatment spec: SELECT first_value(b) IGNORE NULLS OVER (<window spec>)
        | (RPAREN (nt=null_treatment)? KW_OVER) => (RPAREN ((nt=null_treatment)? (KW_OVER ws=window_specification[$nt.tree])))
        // Non-standard null treatment spec: SELECT first_value(b IGNORE NULLS) OVER (<window spec>)
        | (nt=null_treatment) RPAREN (KW_OVER ws=window_specification[$nt.tree])
        | RPAREN
      )
           -> {$star != null}? ^(TOK_FUNCTIONSTAR functionName $ws?)
           -> {$within != null}? ^(TOK_FUNCTION functionName (selectExpression+)? ^(TOK_WITHIN_GROUP $ordBy))
           -> {$dist == null}? ^(TOK_FUNCTION functionName (selectExpression+)? $ws?)
                            -> ^(TOK_FUNCTIONDI functionName (selectExpression+)? $ws?)
    ;

null_treatment
@init { gParent.pushMsg("null_treatment", state); }
@after { gParent.popMsg(state); }
    : KW_RESPECT KW_NULLS -> TOK_RESPECT_NULLS
    | KW_IGNORE KW_NULLS -> TOK_IGNORE_NULLS
    ;

functionName
@init { gParent.pushMsg("function name", state); }
@after { gParent.popMsg(state); }
    : // Keyword IF is also a function name
    functionIdentifier
    |
    sql11ReservedKeywordsUsedAsFunctionName -> Identifier[$sql11ReservedKeywordsUsedAsFunctionName.start]
    ;

castExpression
@init { gParent.pushMsg("cast expression", state); }
@after { gParent.popMsg(state); }
    :
    KW_CAST
    LPAREN
          expression
          KW_AS
          toType=type
          (fmt=KW_FORMAT StringLiteral)?
    RPAREN
    // simple cast
    -> {$fmt == null}? ^(TOK_FUNCTION $toType expression)

    // plain cast ... format: toType is int representing a TOK_* in HiveParser_IdentifiersParser, expression, format pattern
    -> {((CommonTree)toType.getTree()).getChild(0) == null}?
       ^(TOK_FUNCTION {adaptor.create(Identifier, "cast_format")} NumberLiteral[Integer.toString(((CommonTree)toType.getTree()).token.getType())] expression StringLiteral)

    // cast ... format to type with 4th parameter which is length of CHAR or VARCHAR
    -> ^(TOK_FUNCTION {adaptor.create(Identifier, "cast_format")} NumberLiteral[Integer.toString(((CommonTree)toType.getTree()).token.getType())] expression StringLiteral NumberLiteral[((CommonTree)toType.getTree()).getChild(0).getText()])
    ;

whenExpression
@init { gParent.pushMsg("case expression", state); }
@after { gParent.popMsg(state); }
    :
    KW_CASE
     ( KW_WHEN expression KW_THEN expression)+
    (KW_ELSE expression)?
    KW_END -> ^(TOK_FUNCTION KW_WHEN expression*)
    ;

// Make caseExpression to build a whenExpression tree
// Rewrite
// CASE a
//   WHEN b THEN c
//   [WHEN d THEN e]* [ELSE f]
// END
// to
// CASE
//   WHEN a=b THEN c
//   [WHEN a=d THEN e]* [ELSE f]
// END
caseExpression
@init { gParent.pushMsg("case expression", state); }
@after { gParent.popMsg(state); }
    :
    KW_CASE caseOperand=expression
    // Pass the case operand to the rule parses the when branches
    whenBranches[$caseOperand.tree]
    (KW_ELSE elseResult=expression)?
    KW_END -> ^(TOK_FUNCTION Identifier["when"] whenBranches $elseResult?)
    ;

whenBranches[CommonTree caseOperand]
    :
    (whenExpressionBranch[caseOperand] KW_THEN! expression)+
    ;

whenExpressionBranch[CommonTree caseOperand]
    :
    KW_WHEN when=expression
    -> ^(EQUAL["="] {$caseOperand} $when)
    ;

floorExpression
    :
    KW_FLOOR
    LPAREN
          expression
          (KW_TO
          (floorUnit=floorDateQualifiers))?
    RPAREN
    -> {floorUnit != null}? ^(TOK_FUNCTION $floorUnit expression)
    -> ^(TOK_FUNCTION Identifier["floor"] expression)
    ;

floorDateQualifiers
    :
    KW_YEAR -> Identifier["floor_year"]
    | KW_QUARTER -> Identifier["floor_quarter"]
    | KW_MONTH -> Identifier["floor_month"]
    | KW_WEEK -> Identifier["floor_week"]
    | KW_DAY -> Identifier["floor_day"]
    | KW_HOUR -> Identifier["floor_hour"]
    | KW_MINUTE -> Identifier["floor_minute"]
    | KW_SECOND -> Identifier["floor_second"]
    ;

extractExpression
    :
    KW_EXTRACT
    LPAREN
          (timeUnit=timeQualifiers)
          KW_FROM
          expression
    RPAREN -> ^(TOK_FUNCTION $timeUnit expression)
    ;

timeQualifiers
    :
    KW_YEAR -> Identifier["year"]
    | KW_QUARTER -> Identifier["quarter"]
    | KW_MONTH -> Identifier["month"]
    | KW_WEEK -> Identifier["weekofyear"]
    | KW_DAY -> Identifier["day"]
    | KW_DOW -> Identifier["dayofweek"]
    | KW_HOUR -> Identifier["hour"]
    | KW_MINUTE -> Identifier["minute"]
    | KW_SECOND -> Identifier["second"]
    ;

timeUnitQualifiers
    :
    KW_DAY -> Identifier["days"]
    | KW_HOUR -> Identifier["hours"]
    | KW_MINUTE -> Identifier["minutes"]
    ;

constant
@init { gParent.pushMsg("constant", state); }
@after { gParent.popMsg(state); }
    : 
    (intervalLiteral) => intervalLiteral
    | Number
    | dateLiteral
    | timestampLiteral
    | timestampLocalTZLiteral
    | StringLiteral
    | stringLiteralSequence
    | IntegralLiteral
    | NumberLiteral
    | charSetStringLiteral
    | booleanValue
    | KW_NULL -> TOK_NULL
    | prepareStmtParam
    ;

prepareStmtParam
  : p=parameterIdx
  ->
  {
    adaptor.create(TOK_PARAMETER, Integer.toString($p.idx))
  }
  ;

parameterIdx returns [int idx]
  : QUESTION
  { $idx = getParameterIdx(); }
  ->
  {
  adaptor.create(TOK_PARAMETER_IDX, Integer.toString($idx) )
  }
  ;


stringLiteralSequence
    :
    StringLiteral StringLiteral+ -> ^(TOK_STRINGLITERALSEQUENCE StringLiteral StringLiteral+)
    ;

charSetStringLiteral
@init { gParent.pushMsg("character string literal", state); }
@after { gParent.popMsg(state); }
    :
    csName=CharSetName csLiteral=CharSetLiteral -> ^(TOK_CHARSETLITERAL $csName $csLiteral)
    ;

dateLiteral
    :
    KW_DATE StringLiteral ->
    {
      // Create DateLiteral token, but with the text of the string value
      // This makes the dateLiteral more consistent with the other type literals.
      adaptor.create(TOK_DATELITERAL, $StringLiteral.text)
    }
    |
    KW_CURRENT_DATE -> ^(TOK_FUNCTION KW_CURRENT_DATE)
    ;

timestampLiteral
    :
    KW_TIMESTAMP StringLiteral ->
    {
      adaptor.create(TOK_TIMESTAMPLITERAL, $StringLiteral.text)
    }
    |
    KW_CURRENT_TIMESTAMP -> ^(TOK_FUNCTION KW_CURRENT_TIMESTAMP)
    ;

timestampLocalTZLiteral
    :
    KW_TIMESTAMPLOCALTZ StringLiteral ->
    {
      adaptor.create(TOK_TIMESTAMPLOCALTZLITERAL, $StringLiteral.text)
    }
    ;

intervalValue
    :
    StringLiteral | Number
    ;

intervalLiteral
    :
    value=intervalValue qualifiers=intervalQualifiers
    -> ^(TOK_FUNCTION Identifier["internal_interval"] NumberLiteral[Integer.toString(((CommonTree)qualifiers.getTree()).token.getType())] $value)
    ;

intervalExpression
    :
    LPAREN value=intervalValue RPAREN qualifiers=intervalQualifiers
    -> ^(TOK_FUNCTION Identifier["internal_interval"] NumberLiteral[Integer.toString(((CommonTree)qualifiers.getTree()).token.getType())] $value)
    |
    KW_INTERVAL value=intervalValue qualifiers=intervalQualifiers
    -> ^(TOK_FUNCTION Identifier["internal_interval"] NumberLiteral[Integer.toString(((CommonTree)qualifiers.getTree()).token.getType())] $value)
    |
    KW_INTERVAL LPAREN expr=expression RPAREN qualifiers=intervalQualifiers
    -> ^(TOK_FUNCTION Identifier["internal_interval"] NumberLiteral[Integer.toString(((CommonTree)qualifiers.getTree()).token.getType())] $expr)
    ;

intervalQualifiers
    :
    (KW_YEAR KW_TO) => KW_YEAR KW_TO KW_MONTH -> TOK_INTERVAL_YEAR_MONTH_LITERAL
    | (KW_DAY KW_TO) => KW_DAY KW_TO KW_SECOND -> TOK_INTERVAL_DAY_TIME_LITERAL
    | KW_YEAR -> TOK_INTERVAL_YEAR_LITERAL
    | KW_MONTH -> TOK_INTERVAL_MONTH_LITERAL
    | KW_DAY -> TOK_INTERVAL_DAY_LITERAL
    | KW_HOUR -> TOK_INTERVAL_HOUR_LITERAL
    | KW_MINUTE -> TOK_INTERVAL_MINUTE_LITERAL
    | KW_SECOND -> TOK_INTERVAL_SECOND_LITERAL
    ;

expression
@init { gParent.pushMsg("expression specification", state); }
@after { gParent.popMsg(state); }
    :
    precedenceOrExpression
    ;

atomExpression
    :
    constant
    | (intervalExpression) => intervalExpression
    | castExpression
    | extractExpression
    | floorExpression
    | caseExpression
    | whenExpression
    | (subQueryExpression)=> (subQueryExpression)
        -> ^(TOK_SUBQUERY_EXPR TOK_SUBQUERY_OP subQueryExpression)
    | (functionName LPAREN) => function
    | tableOrColumn
    | expressionsInParenthesis[true, false]
    ;

precedenceFieldExpression
    :
    atomExpression ((LSQUARE^ expression RSQUARE!) | (DOT^ identifier))*
    ;

precedenceUnaryOperator
    :
    PLUS | MINUS | TILDE
    ;

precedenceUnaryPrefixExpression
    :
    (precedenceUnaryOperator^)* precedenceFieldExpression
    ;


precedenceBitwiseXorOperator
    :
    BITWISEXOR
    ;

precedenceBitwiseXorExpression
    :
    precedenceUnaryPrefixExpression (precedenceBitwiseXorOperator^ precedenceUnaryPrefixExpression)*
    ;


precedenceStarOperator
    :
    STAR | DIVIDE | MOD | DIV
    ;

precedenceStarExpression
    :
    precedenceBitwiseXorExpression (precedenceStarOperator^ precedenceBitwiseXorExpression)*
    ;


precedencePlusOperator
    :
    PLUS | MINUS
    ;

precedencePlusExpression
    :
    precedenceStarExpression (precedencePlusOperator^ precedenceStarExpression)*
    ;

precedenceConcatenateOperator
    :
    CONCATENATE
    ;

precedenceConcatenateExpression
    :
    (precedencePlusExpression -> precedencePlusExpression)
        (
        precedenceConcatenateOperator plus=precedencePlusExpression
        -> ^(TOK_FUNCTION {adaptor.create(Identifier, "concat")} {$precedenceConcatenateExpression.tree} $plus)
        )*
    -> {$precedenceConcatenateExpression.tree}
    ;

precedenceAmpersandOperator
    :
    AMPERSAND
    ;

precedenceAmpersandExpression
    :
    precedenceConcatenateExpression (precedenceAmpersandOperator^ precedenceConcatenateExpression)*
    ;


precedenceBitwiseOrOperator
    :
    BITWISEOR
    ;

precedenceBitwiseOrExpression
    :
    precedenceAmpersandExpression (precedenceBitwiseOrOperator^ precedenceAmpersandExpression)*
    ;


precedenceRegexpOperator
    :
    KW_LIKE | KW_RLIKE | KW_REGEXP
    ;

precedenceSimilarOperator
    :
    precedenceRegexpOperator | LESSTHANOREQUALTO | LESSTHAN | GREATERTHANOREQUALTO | GREATERTHAN
    ;

subQueryExpression
    :
    LPAREN! selectStatement RPAREN!
    ;

precedenceSimilarExpression
    :
    precedenceSimilarExpressionMain
    |
    KW_EXISTS subQueryExpression -> ^(TOK_SUBQUERY_EXPR ^(TOK_SUBQUERY_OP KW_EXISTS) subQueryExpression)    
    ;

precedenceSimilarExpressionMain
    :
    a=precedenceBitwiseOrExpression part=precedenceSimilarExpressionPart[$precedenceBitwiseOrExpression.tree]?
    -> {part == null}? {$a.tree}
    -> {$part.tree}
    ;
    
precedenceSimilarExpressionPart[CommonTree t]
    :
    (precedenceSimilarOperator equalExpr=precedenceBitwiseOrExpression)
    -> ^(precedenceSimilarOperator {$t} $equalExpr)
    |
    precedenceSimilarExpressionAtom[$t]
    |
    (KW_NOT^ precedenceSimilarExpressionPartNot[$t])
    ;

precedenceSimilarExpressionAtom[CommonTree t]
    :
    KW_IN! precedenceSimilarExpressionIn[$t]
    |
    KW_BETWEEN (min=precedenceBitwiseOrExpression) KW_AND (max=precedenceBitwiseOrExpression)
    -> ^(TOK_FUNCTION Identifier["between"] KW_FALSE {$t} $min $max)
    |
    KW_LIKE KW_ANY (expr=expressionsInParenthesis[false, false])
    -> ^(TOK_FUNCTION Identifier["likeany"] {$t} {$expr.tree})
    |
    KW_LIKE KW_ALL (expr=expressionsInParenthesis[false, false])
    -> ^(TOK_FUNCTION Identifier["likeall"] {$t} {$expr.tree})
    |
    precedenceSimilarExpressionQuantifierPredicate[$t]
    ;

precedenceSimilarExpressionQuantifierPredicate[CommonTree t]
    :
    subQuerySelectorOperator quantifierType subQueryExpression
    -> ^(TOK_SUBQUERY_EXPR ^(TOK_SUBQUERY_OP quantifierType subQuerySelectorOperator ) subQueryExpression {$t})
    ;

quantifierType
    :
    KW_ANY -> KW_SOME
    |
    KW_SOME -> KW_SOME
    |
    KW_ALL -> KW_ALL
    ;

precedenceSimilarExpressionIn[CommonTree t]
    :
    (subQueryExpression) => subQueryExpression -> ^(TOK_SUBQUERY_EXPR ^(TOK_SUBQUERY_OP KW_IN) subQueryExpression {$t})
    |
    expr=expressionsInParenthesis[false, false]
    -> ^(TOK_FUNCTION Identifier["in"] {$t} {$expr.tree})
    ;

precedenceSimilarExpressionPartNot[CommonTree t]
    :
    precedenceRegexpOperator notExpr=precedenceBitwiseOrExpression
    -> ^(precedenceRegexpOperator {$t} $notExpr)
    |
    precedenceSimilarExpressionAtom[$t]
    ;

precedenceDistinctOperator
    :
    KW_IS KW_DISTINCT KW_FROM
    ;

precedenceEqualOperator
    :
    EQUAL | EQUAL_NS | NOTEQUAL | KW_IS KW_NOT KW_DISTINCT KW_FROM -> EQUAL_NS["<=>"]
    ;

precedenceEqualExpression
    :
    (precedenceSimilarExpression -> precedenceSimilarExpression)
    (
        equal=precedenceEqualOperator p=precedenceSimilarExpression
        -> ^($equal {$precedenceEqualExpression.tree} $p)
        |
        dist=precedenceDistinctOperator p=precedenceSimilarExpression
        -> ^(KW_NOT["not"] ^(EQUAL_NS["<=>"] {$precedenceEqualExpression.tree} $p))
    )*
    -> {$precedenceEqualExpression.tree}
    ;

isCondition
    : KW_NULL -> Identifier["isnull"]
    | KW_TRUE -> Identifier["istrue"]
    | KW_FALSE -> Identifier["isfalse"]
    | KW_UNKNOWN -> Identifier["isnull"]
    | KW_NOT KW_NULL -> Identifier["isnotnull"]
    | KW_NOT KW_TRUE -> Identifier["isnottrue"]
    | KW_NOT KW_FALSE -> Identifier["isnotfalse"]
    | KW_NOT KW_UNKNOWN -> Identifier["isnotnull"]
    ;

precedenceUnarySuffixExpression
    : precedenceEqualExpression (a=KW_IS isCondition)?
    -> {$a != null}? ^(TOK_FUNCTION isCondition precedenceEqualExpression)
    -> precedenceEqualExpression
    ;
    
precedenceNotOperator
    :
    KW_NOT
    ;

precedenceNotExpression
    :
    (precedenceNotOperator^)* precedenceUnarySuffixExpression
    ;


precedenceAndOperator
    :
    KW_AND
    ;

precedenceAndExpression
    :
    precedenceNotExpression (precedenceAndOperator^ precedenceNotExpression)*
    ;


precedenceOrOperator
    :
    KW_OR
    ;

precedenceOrExpression
    :
    precedenceAndExpression (precedenceOrOperator^ precedenceAndExpression)*
    ;


booleanValue
    :
    KW_TRUE^ | KW_FALSE^
    ;

booleanValueTok
   :
   KW_TRUE -> TOK_TRUE
   | KW_FALSE -> TOK_FALSE
   ;

tableOrPartition
   :
   tableName partitionSpec? -> ^(TOK_TAB tableName partitionSpec?)
   ;

partitionSpec
    :
    KW_PARTITION
     LPAREN partitionVal (COMMA  partitionVal )* RPAREN -> ^(TOK_PARTSPEC partitionVal +)
    ;

partitionVal
    :
    identifier (EQUAL constant)? -> ^(TOK_PARTVAL identifier constant?)
    | functionExpr (EQUAL constant)? -> ^(TOK_PARTVAL functionExpr constant?)
    ;

partitionSelectorSpec
    :
    LPAREN partitionSelectorVal (COMMA  partitionSelectorVal )* RPAREN -> ^(TOK_PARTSPEC partitionSelectorVal +)
    ;

partitionSelectorVal
    :
    identifier partitionSelectorOperator constant -> ^(TOK_PARTVAL identifier partitionSelectorOperator constant)
    | functionExpr partitionSelectorOperator constant -> ^(TOK_PARTVAL functionExpr partitionSelectorOperator constant)
    ;

functionExpr
    :
    funcName LPAREN identifier RPAREN -> ^(TOK_FUNCTION funcName identifier)
    | KW_TRUNCATE LPAREN width=Number COMMA identifier RPAREN -> ^(TOK_FUNCTION KW_TRUNCATE $width identifier)
    | KW_BUCKET LPAREN width=Number COMMA identifier RPAREN -> ^(TOK_FUNCTION KW_BUCKET $width identifier)
    ;

funcName
    :
    KW_DAY
    | KW_MONTH
    | KW_YEAR
    | KW_HOUR
    ;


partitionSelectorOperator
    :
    KW_LIKE | subQuerySelectorOperator
    ;

subQuerySelectorOperator
    :
    EQUAL | NOTEQUAL | LESSTHANOREQUALTO | LESSTHAN | GREATERTHANOREQUALTO | GREATERTHAN
    ;

sysFuncNames
    :
      KW_AND
    | KW_OR
    | KW_NOT
    | KW_LIKE
    | KW_IF
    | KW_CASE
    | KW_WHEN
    | KW_FLOOR
    | KW_TINYINT
    | KW_SMALLINT
    | KW_INT
    | KW_BIGINT
    | KW_FLOAT
    | KW_REAL
    | KW_DOUBLE
    | KW_BOOLEAN
    | KW_STRING
    | KW_BINARY
    | KW_ARRAY
    | KW_MAP
    | KW_STRUCT
    | KW_UNIONTYPE
    | EQUAL
    | EQUAL_NS
    | NOTEQUAL
    | LESSTHANOREQUALTO
    | LESSTHAN
    | GREATERTHANOREQUALTO
    | GREATERTHAN
    | DIVIDE
    | PLUS
    | MINUS
    | STAR
    | MOD
    | DIV
    | AMPERSAND
    | TILDE
    | BITWISEOR
    | BITWISEXOR
    | KW_RLIKE
    | KW_REGEXP
    | KW_IN
    | KW_BETWEEN
    ;

descFuncNames
    :
      (sysFuncNames) => sysFuncNames
    | StringLiteral
    | functionIdentifier
    ;

identifier
    :
    Identifier
    | nonReserved -> Identifier[$nonReserved.start]
    ;

functionIdentifier
@init { gParent.pushMsg("function identifier", state); }
@after { gParent.popMsg(state); }
    : db=identifier DOT fn=identifier
    -> Identifier[$db.text + "." + $fn.text]
    |
    identifier
    ;

principalIdentifier
@init { gParent.pushMsg("identifier for principal spec", state); }
@after { gParent.popMsg(state); }
    : identifier
    | QuotedIdentifier
    ;

// Here is what you have to do if you would like to add a new keyword.
// Note that non reserved keywords are basically the keywords that can be used as identifiers.
// (1) Add a new entry to HiveLexer, e.g., KW_TRUE : 'TRUE';
// (2) If it is reserved, you do NOT need to change IdentifiersParser.g
//                        because all the KW_* are automatically not only keywords, but also reserved keywords.
//                        However, you need to add a test to TestSQL11ReservedKeyWordsNegative.java.
//     Otherwise it is non-reserved, you need to put them in the nonReserved list below.
//If you are not sure, please refer to the SQL2011 column in
//http://www.postgresql.org/docs/9.5/static/sql-keywords-appendix.html
nonReserved
    :
    KW_ABORT | KW_ADD | KW_ADMIN | KW_AFTER | KW_ANALYZE | KW_ARCHIVE | KW_ASC | KW_BEFORE | KW_BUCKET | KW_BUCKETS
    | KW_CASCADE | KW_CBO | KW_CHANGE | KW_CHECK | KW_CLUSTER | KW_CLUSTERED | KW_CLUSTERSTATUS | KW_COLLECTION | KW_COLUMNS
    | KW_COMMENT | KW_COMPACT | KW_COMPACTIONS | KW_COMPUTE | KW_CONCATENATE | KW_CONTINUE | KW_COST | KW_DATA | KW_DAY | KW_CATALOG | KW_CATALOGS
    | KW_DATABASES | KW_DATETIME | KW_DBPROPERTIES | KW_DCPROPERTIES | KW_DEFERRED | KW_DEFINED | KW_DELIMITED | KW_DEPENDENCY
    | KW_DESC | KW_DIRECTORIES | KW_DIRECTORY | KW_DISABLE | KW_DISTRIBUTE | KW_DISTRIBUTED | KW_DOW | KW_ELEM_TYPE
    | KW_ENABLE | KW_ENFORCED | KW_ESCAPED | KW_EXCLUSIVE | KW_EXPLAIN | KW_EXPORT | KW_FIELDS | KW_FILE | KW_FILEFORMAT
    | KW_FIRST | KW_FORMAT | KW_FORMATTED | KW_FUNCTIONS | KW_HOUR | KW_IDXPROPERTIES | KW_RESPECT | KW_IGNORE
    | KW_INDEX | KW_INDEXES | KW_INPATH | KW_INPUTDRIVER | KW_INPUTFORMAT | KW_ITEMS | KW_JAR | KW_JOINCOST | KW_KILL
    | KW_KEYS | KW_KEY_TYPE | KW_LAST | KW_LIMIT | KW_OFFSET | KW_LINES | KW_LOAD | KW_LOCATION | KW_LOCK | KW_LOCKS | KW_LOGICAL | KW_LONG | KW_MANAGED
    | KW_MANAGEDLOCATION | KW_MAPJOIN | KW_MATERIALIZED | KW_METADATA | KW_MINUTE | KW_MONTH | KW_MSCK | KW_NOSCAN | KW_NULLS
    | KW_OPTION | KW_OUTPUTDRIVER | KW_OUTPUTFORMAT | KW_OVERWRITE | KW_OWNER | KW_PARTITIONED | KW_PARTITIONS | KW_PLUS
    | KW_PRINCIPALS | KW_PURGE | KW_QUERY | KW_QUARTER | KW_READ | KW_REBUILD | KW_RECORDREADER | KW_RECORDWRITER
    | KW_RELOAD | KW_REMOTE | KW_RENAME | KW_REPAIR | KW_REPLACE | KW_REPLICATION | KW_RESTRICT | KW_REWRITE
    | KW_ROLE | KW_ROLES | KW_SCHEMA | KW_SCHEMAS | KW_SECOND | KW_SEMI | KW_SERDE | KW_SERDEPROPERTIES | KW_SERVER | KW_SETS | KW_SHARED
    | KW_SHOW | KW_SHOW_DATABASE | KW_SKEWED | KW_SORT | KW_SORTED | KW_SSL | KW_STATISTICS | KW_STORED | KW_AST
    | KW_STREAMTABLE | KW_STRING | KW_STRUCT | KW_TABLES | KW_TBLPROPERTIES | KW_TEMPORARY | KW_TERMINATED
    | KW_TINYINT | KW_TOUCH | KW_TRANSACTIONAL | KW_TRANSACTIONS | KW_TYPE | KW_UNARCHIVE | KW_UNDO | KW_UNIONTYPE | KW_UNLOCK | KW_UNSET
    | KW_UNSIGNED | KW_URI | KW_URL | KW_USE | KW_UTC | KW_UTCTIMESTAMP | KW_VALUE_TYPE | KW_VIEW | KW_WEEK | KW_WHILE | KW_YEAR
    | KW_WORK
    | KW_TRANSACTION
    | KW_WRITE
    | KW_ISOLATION
    | KW_LEVEL
    | KW_SNAPSHOT
    | KW_AUTOCOMMIT
    | KW_RELY
    | KW_NORELY
    | KW_VALIDATE
    | KW_NOVALIDATE
    | KW_KEY
    | KW_MATCHED
    | KW_REPL | KW_DUMP | KW_STATUS
    | KW_CACHE | KW_VIEWS
    | KW_VECTORIZATION
    | KW_SUMMARY
    | KW_OPERATOR
    | KW_EXPRESSION
    | KW_DETAIL
    | KW_DEBUG
    | KW_WAIT
    | KW_ZONE
    | KW_DEFAULT
    | KW_REOPTIMIZATION
    | KW_EXECUTED | KW_SCHEDULED | KW_CRON | KW_EVERY | KW_AT | KW_EXECUTE
    | KW_RESOURCE | KW_PLAN | KW_PLANS | KW_QUERY_PARALLELISM | KW_ACTIVATE | KW_MOVE | KW_DO
    | KW_POOL | KW_ALLOC_FRACTION | KW_SCHEDULING_POLICY | KW_PATH | KW_MAPPING | KW_WORKLOAD | KW_MANAGEMENT | KW_ACTIVE | KW_UNMANAGED
    | KW_UNKNOWN
    | KW_WITHIN
    | KW_TRIM
    | KW_SPEC
    | KW_SYSTEM_TIME | KW_SYSTEM_VERSION
    | KW_EXPIRE_SNAPSHOTS
    | KW_SET_CURRENT_SNAPSHOT
    | KW_BRANCH | KW_SNAPSHOTS | KW_RETAIN | KW_RETENTION
    | KW_TAG
    | KW_FAST_FORWARD
    | KW_OPTIMIZE
    | KW_APPLICATION
    | KW_COMPACT_ID
    | KW_DATACONNECTOR
    | KW_DATACONNECTORS
    | KW_DDL
    | KW_FORCE
    | KW_OLDER
    | KW_PKFK_JOIN
    | KW_THAN
    | KW_TIMESTAMPLOCALTZ
    | KW_ORDERED
    | KW_LOCALLY
;

//The following SQL2011 reserved keywords are used as function name only, but not as identifiers.
sql11ReservedKeywordsUsedAsFunctionName
    :
    KW_IF | KW_ARRAY | KW_MAP | KW_BIGINT | KW_BINARY | KW_BOOLEAN | KW_CURRENT_DATE | KW_CURRENT_TIMESTAMP | KW_DATE | KW_DOUBLE | KW_FLOAT | KW_REAL | KW_GROUPING | KW_INT | KW_SMALLINT | KW_TIMESTAMP
    ;
