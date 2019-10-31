Glossary
========

*********
Condition
*********
    A question that a specific oracle reports on with a preset number of outcome slots. Analogous to events from Gnosis' first prediction market contracts.

    For example, a condition with a categorical outcome, that is, one of N outcomes, may have N outcome slots, where the resolution of the condition sets one of the outcome slots to receive the full payout.

    Another example: a condition with a scalar outcome, that is an outcome X in some range [A, B], may have two outcome slots which correspond to the ends of the range A and B. Both slots are set to receive a proportion of the payout according to how close the outcome X is to A or B.

    *Identified by keccak256(oracle . questionId . outcomeSlotCount)*

    **Outcome Slot**
        Defines the redemption rate of Conditional Tokens. Conditional Tokens convert to a proportion of collateral depending on the outcome resolution of a set of conditions. 

        Outcome Slots can either be unresolved (when the condition hasn’t been reported on) or resolved (after condition resolution). 

        **Index Set**
            A bit array that represents a subset of Outcome Slots in one condition.

            Example: Condition1 has Outcome Slots: A,B,C. It would have 7 possible indexSets: A, B, C, A|B, A|C, B|C, A|B,C

        **Partition**
            A specific way to separate the subsets of the Outcome Slots in a condition, using a combination of indexSets.

    **Oracle**
        The account which can report the results on the condition.

    **Outcome Resolution**
        The process in which an oracle reports results for the Outcome Slots in a condition, setting the Outcome Slot value for each of the condition’s Outcome Slots.

*********
Position
*********
    A set of conditions, along with a non-empty proper subset of Outcome Slots for each condition (represents a combination of one or many Outcome Slots from multiple conditions) represented as a DAG (Directed Acyclic Graph) and tied to a specific stakeholder, Collateral Token, and amount of Conditional Tokens. 

    Representing a specific stakeholders stake in a certain condition(s) Outcome Slots as an ERC1155 token.

    A position is made up of: 
     1. Stakeholder
        Collection Identifier
        Condition(s)
        IndexSet(s)
        CollateralToken
        Conditional Tokens

    *Identified by the hash of a H(Collateral Token, Collection Identifier)*

    **Collection Identifier**
        An identifier used by positions to target Condition(s) and indexSet(s). 

        Rather than target individual Conditions and IndexSets. The Condition Identifier can identify a DAG (Directed Acyclic Graph) of dependant Condition(s) and indexSet(s).

        It is the abstract structure that identifies what Conditions and IndexSets, a position is representing, along with their heirarchy. Without being tied to any specific stakeholder or Collateral Token.

        If the parentCollectionId is equal to 0, then it is a Root Position. 

        Identified by a sum( parentCollectionIdentifier, hash(ConditionIdentifier . indexSet)

    **Collateral Token**
        An ERC20 token used to create stake in positions.

    **Conditional Tokens**
        For a given Collection Identifier, a stakeholder may express a belief in what that Collection Identifier of Outcome Slots represents by using a collateral token to create a position from the Collection Identifier and holding Conditional Tokens in that slot.

        For non-root positions, redemption will convert Conditional Tokens into stake in a shallower position. For root positions, redemption will convert Conditional Tokens into Collateral Tokens.

    **Position Depth**
        The number of conditions a position is based off of. Terminology is chosen because positions form a DAG which is very tree-like. Shallow positions have few conditions, and deep positions have many conditions.

        **Root Position**
            A position based off of only a single condition. Pays out depending on the outcome of the condition. Pays out directly to the Collateral Token
        
        **Non-Root Position**
            A position based off of multiple conditions. Pays out depending on all of the outcomes of the multiple conditions. Pays out to a shallower Position.

        **Atomic Position**
            A position is atomic with respect to a set of conditions if it is contingent on all of the conditions in that set. Pays out to a shallower Position.

    **Splitting a Position**
        Stakeholders can split a position on an optional collection identifier and a condition.

        For Root Positions, a collection identifier is not given (instead it is 0), and the stakeholder transfers an input amount of collateral tokens in order to get an equal amount of conditional tokens in each of the condition’s outcome slots.

        For Non-Root Positions, a parent Collection Identifier is provided, and the stakeholder transfers an input amount of Conditional Tokens from the Position corresponding to the parent Collection Identifier down to a set of new Non-Root Position(s). 

        Results in conditional tokens being transferred from the position being split to the positions resulting from the split. 

    **Merging a Position**
        Basically the opposite of splitting a position. Stakeholders can merge a position on an optional Outcome Slot and a Collection Identifier for non-root positions.

        For Root Positions, if an Outcome Slot is not given, the stakeholder inputs an equal amount of Conditional Tokens in each of the condition’s root Outcome Slots to receive an equal amount of Collateral Tokens.

        For Non-Root Positions, a parent Collection Identifier is provided, and the stakeholder transfers an input amount of Conditional Tokens from all the Outcome Slots input in the partition[] either up to a position identified by the parent Collection Identifier or merged into a single Position. 

        Results in conditional tokens being transferred from the positions being merged to the position resulting from the merge. 

    **Redeeming Positions**
        Redeems (1 - all Index Sets) of Positions that are predicated on a single Condition and collection identifier.

        Resulting in either more Conditional Tokens in a shallower position, or a conversion of Conditional Tokens into the Collateral Token, depending on whether it’s a Root Position or Non-Root Position. 
	
        To redeem a position, you need:
         1. The Collateral Token that position is tied to. 
            It’s parent positions Collection Identifier (if it has one), otherwise it would be a Root Position, and you would input 0 to receive back Collateral Tokens.
            The condition you want to redeem.
            The Index Sets[] you want to redeem. 

        This will redeem all of the Index Sets[] slots listed in the given condition, for only positions with a parent position that has a Collection Idenfier equal to parentCollectionId. 





