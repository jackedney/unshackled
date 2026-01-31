# Agent Skills Documentation

This document describes all agent capabilities in the Unshackled reasoning registry. Each agent implements the `Unshackled.Agents.Agent` behaviour and follows a standardized pattern for skill, expertise, and confidence delta.

## Agent Activation Schedule

- **Core Agents** (every cycle): Explorer, Critic
- **Analytical Agents** (every 3 cycles): Connector, Steelman, Operationalizer, Quantifier
- **Structural Agents** (every 5 cycles): Reducer, Boundary Hunter, Translator, Historian
- **Meta-Agents** (conditional): Grave Keeper, Cartographer, Perturber
- **Special Agents**: Summarizer (runs independently, not cycle-based)

---

## Core Agents

### Explorer

**Skill**: Extend claims by one inferential step

**Expertise**: Inferential step generation through deductive, inductive, or abductive reasoning

**Logical constraints**:
- Must extend claim by exactly one step
- Must commit to extension without hedging or uncertainty language
- Forbidden: "might", "possibly", "perhaps", "maybe", "could be", "seems", "appears", "likely", "probably", "would seem"
- Forbidden transitional opening words: "Therefore", "Consequently", "Thus", "Hence", "As a result", "Accordingly", "So", "In conclusion"
- New claim must start with subject (noun phrase), not transitional word
- Must specify inference type: deductive, inductive, or abductive

**Confidence delta**: `+0.10` (valid response), `0.0` (invalid)

**Reasoning frequency**: Every cycle

**Response fields**:
- `new_claim` (string): The definitive extension of the claim
- `inference_type` (string): One of "deductive", "inductive", "abductive"
- `reasoning` (string, optional): Brief explanation of the inference
- `valid` (boolean): Whether response was properly formatted

---

### Critic

**Skill**: Attack the weakest premise of claims

**Expertise**: Premise identification and objection formulation

**Logical constraints**:
- Must attack a PREMISE, not the conclusion or result
- Must formulate specific objection to identified premise
- Must ask clarifying question probing the foundation
- Forbidden: Targeting conclusion/result markers ("therefore", "thus", "consequently", "hence", "so", "as a result")
- Forbidden: General skepticism without specific premise focus
- Forbidden: Vague rejection like "This is wrong because" without identifying which premise

**Confidence delta**: `-0.15` (valid response), `0.0` (invalid)

**Reasoning frequency**: Every cycle

**Response fields**:
- `objection` (string): Specific objection to a premise
- `target_premise` (string): The exact premise being objected to
- `clarifying_question` (string): Question probing this premise
- `reasoning` (string, optional): Explanation of why premise is weak
- `valid` (boolean): Whether response was properly formatted

---

## Analytical Agents

### Connector

**Skill**: Find cross-domain analogies

**Expertise**: Cross-domain analogy mapping and testable structure

**Logical constraints**:
- Must identify domain DIFFERENT from claim's domain
- Must find specific phenomenon or principle in that domain
- Must provide clear, specific mapping explanation
- Forbidden: Vague analogies like "many things in nature", "various phenomena", "like many things"
- Forbidden: Same domain analogies (e.g., physics → physics)
- Must follow format "This is like X because Y"
- Must be specific enough to test

**Confidence delta**: `+0.05` (valid response), `0.0` (invalid)

**Reasoning frequency**: Every 3 cycles

**Response fields**:
- `analogy` (string): The specific analogy following format "This is like X because Y"
- `source_domain` (string): Domain drawing from (e.g., information theory, economics, biology)
- `mapping_explanation` (string): Detailed explanation of domain mapping
- `valid` (boolean): Whether response was properly formatted

---

### Steelman

**Skill**: Construct strongest opposing view

**Expertise**: Counter-argument construction without advocacy

**Logical constraints**:
- Must construct, NOT advocate for opposing view
- Must present opposing view neutrally
- Must use neutral attribution: "The opposing view is...", "One could argue...", "Some might contend..."
- Forbidden: Taking ownership ("I believe", "I argue", "I contend")
- Forbidden: Drawing conclusions ("therefore", "thus", "so")
- Forbidden: Normative claims ("must", "should")
- Forbidden: Claiming proof ("proves that", "demonstrates that")
- Must identify key assumptions (non-empty list)
- Must identify strongest point

**Confidence delta**: `-0.05` (valid response), `0.0` (invalid)

**Reasoning frequency**: Every 3 cycles

**Response fields**:
- `counter_argument` (string): Strongest counter-argument presented neutrally
- `key_assumptions` (list): List of assumptions underlying counter-argument
- `strongest_point` (string): Single most compelling point
- `valid` (boolean): Whether response was properly formatted

---

### Operationalizer

**Skill**: Convert claims to falsifiable predictions

**Expertise**: Testable prediction generation with surprise factors

**Logical constraints**:
- Must translate claim into specific, observable prediction
- Must specify exact conditions for observation
- Must describe what would be observed if claim is true
- CRITICAL: Prediction must be SURPRISING (non-obvious)
- Forbidden: Predictions that would be expected regardless of claim
- Forbidden: Obvious prediction indicators ("regardless of", "in any case", "would happen anyway", "expected behavior")
- Must follow format "If true, observe X under Y"

**Confidence delta**: `0.0` (no direct confidence impact - advisory only)

**Reasoning frequency**: Every 3 cycles

**Response fields**:
- `prediction` (string): Full prediction following format "If true, observe X under Y"
- `test_conditions` (string): Specific conditions for observation
- `expected_observation` (string): What would be observed if claim is true
- `surprise_factor` (string): Explanation of why prediction is surprising
- `valid` (boolean): Whether response was properly formatted

---

### Quantifier

**Skill**: Add numerical precision to claims

**Expertise**: Numerical bounds specification with principled justification

**Logical constraints**:
- Must identify places for numerical precision
- Must add specific numerical values, ranges, or parameters
- Must provide principled justification for chosen numbers
- MUST EXPLICITLY STATE whether bounds are ARBITRARY or PRINCIPLED
  - PRINCIPLED: Based on theory, empirical evidence, or known physical/mathematical constants
  - ARBITRARY: Chosen as working hypothesis without strong theoretical justification
- Forbidden: Arbitrary bounds without acknowledgment
- Must contain numerical values or parameters

**Confidence delta**: `+0.05` (valid response), `0.0` (invalid)

**Reasoning frequency**: Every 3 cycles

**Response fields**:
- `quantified_claim` (string): Claim with numerical bounds added
- `bounds` (string): Description of numerical bounds or parameters
- `bounds_justification` (string): Detailed explanation of why specific values were chosen
- `arbitrary_flag` (boolean): True if bounds are arbitrary, false if principled
- `valid` (boolean): Whether response was properly formatted

---

## Structural Agents

### Reducer

**Skill**: Compress claims to their fundamental essence

**Expertise**: Essential logical content extraction while removing elaboration

**Logical constraints**:
- Must identify core logical proposition at heart of claim
- Must remove all elaboration, examples, clarifications, explanatory text
- MUST preserve essential logical content, relationships, and dependencies
- Must state essential claim in clearest, most direct form
- Must list what was removed and what was preserved
- Invalid: Removing key logical terms ("all", "only", "must", "cannot")
- Invalid: Changing universal claims to existential claims
- Invalid: Dropping necessary conditions or qualifiers

**Confidence delta**: `0.0` (no direct confidence impact - purely distillation)

**Reasoning frequency**: Every 5 cycles

**Response fields**:
- `essential_claim` (string): Distilled core proposition
- `removed_elements` (list): Elements removed during reduction
- `preserved_elements` (list): Elements preserved in reduction
- `valid` (boolean): Whether response was properly formatted

---

### Boundary Hunter

**Skill**: Find edge cases where claims break

**Expertise**: Edge case identification and boundary condition analysis

**Logical constraints**:
- Must identify SPECIFIC edge case, boundary condition, or extreme scenario
- Must explain exactly how and why claim breaks in this case
- Must describe consequence or paradox that results
- CRITICAL: Find SPECIFIC edge cases, NOT general skepticism
- Forbidden: General skepticism ("We can never be sure", "cannot be proven", "impossible to verify")
- Forbidden: Epistemological doubts ("beyond testing", "might be wrong", "no way to know")
- Must provide concrete, testable scenario

**Confidence delta**: `-0.10` (valid response), `0.0` (invalid)

**Reasoning frequency**: Every 5 cycles

**Response fields**:
- `edge_case` (string): Specific, testable edge case or boundary condition
- `why_it_breaks` (string): Explanation of how claim fails in this case
- `consequence` (string): Resulting paradox, contradiction, or failure
- `valid` (boolean): Whether response was properly formatted

---

### Translator

**Skill**: Restate claims in different frameworks

**Expertise**: Cross-disciplinary translation revealing hidden assumptions

**Logical constraints**:
- Must identify core structure and assumptions of original claim
- Must map concepts to corresponding terms in target framework
- Must express claim using target framework's terminology
- Must identify what hidden assumptions are revealed
- Target frameworks: physics, information_theory, economics, biology, mathematics
- CRITICAL: Must reveal new insights, not merely rephrase
- Forbidden: Mere rephrasing ("basically means", "essentially same as", "is just another way of saying")
- Forbidden: Framework-generic translation (could apply to any claim)
- Must be meaningful translation with framework-specific insight

**Confidence delta**: `0.0` (no direct confidence impact - perspective only)

**Reasoning frequency**: Every 5 cycles

**Response fields**:
- `translated_claim` (string): Claim restated using target framework's concepts
- `target_framework` (string): One of "physics", "information_theory", "economics", "biology", "mathematics"
- `revealed_assumption` (string): Hidden assumption or structural feature revealed by translation
- `valid` (boolean): Whether response was properly formatted

---

## Meta-Agents

### Historian

**Skill**: Detect re-treading of previous claims

**Expertise**: Novelty assessment through historical claim comparison

**Logical constraints**:
- SPECIAL ACCESS: Has access to previous claims from snapshots (claim text only, NOT reasoning)
- Must compare current claim against all previous claims
- Must identify if current claim is substantially similar to previous claims (re-treading)
- Must list similar claims with cycle numbers
- Must assess novelty score (0.0 to 1.0):
  - 0.0 = Complete re-treading (identical or near-identical)
  - 0.5 = Partial overlap (some similarity with new elements)
  - 1.0 = Completely novel (no meaningful similarity to history)
- MUST base analysis solely on semantic similarity of claim text

**Confidence delta**: `0.0` (no direct confidence impact - advisory only)

**Reasoning frequency**: Every 5 cycles (starting from cycle 5)

**Response fields**:
- `is_retread` (boolean): Whether this is a re-tread
- `similar_claims` (list): List of similar claim texts
- `cycle_numbers` (list): List of cycle numbers with similar claims
- `novelty_score` (float): Float between 0.0 and 1.0
- `analysis` (string, optional): Brief explanation of assessment
- `valid` (boolean): Whether response was properly formatted

---

### Grave Keeper

**Skill**: Track patterns in why ideas die

**Expertise**: Death pattern analysis and survival strategy suggestion

**Logical constraints**:
- SPECIAL ACCESS: Has access to cemetery records of killed claims with cause of death
- Must compare current claim (at risk) against historical deaths
- Must identify patterns in how claims have died
- Must assess death risk (0.0 to 1.0):
  - 0.0 = Very low risk (claim robust against historical death patterns)
  - 0.5 = Moderate risk (some concerning similarities)
  - 1.0 = Very high risk (claim nearly identical to dead claims)
- Must identify similar deaths with cause and similarity reason
- Must detect recurring death patterns
- Must suggest specific modification to help claim survive

**Confidence delta**: `0.0` (no direct confidence impact - advisory only)

**Reasoning frequency**: When support_strength < 0.4 (claim at risk)

**Response fields**:
- `death_risk` (float): Float between 0.0 and 1.0
- `similar_deaths` (list): List of similar death records with claim, cycle_killed, cause_of_death, similarity_reason
- `pattern_detected` (string): Description of death pattern or "none" if no pattern
- `survival_suggestion` (string): Specific modification to help claim survive
- `valid` (boolean): Whether response was properly formatted

---

### Cartographer

**Skill**: Navigate the embedding space

**Expertise**: Trajectory stagnation detection and guidance to underexplored regions

**Logical constraints**:
- SPECIAL ACCESS: Has access to trajectory visualization data from TrajectoryPoint records
- Activates only when stagnation detected (low trajectory movement for 5+ cycles)
- Stagnation threshold: Average movement < 0.1 (normalized distance between embeddings)
- Must include current position, trajectory history, and underexplored regions
- Must suggest direction to move swarm out of current basin
- Must identify target region in underexplored embedding space
- Must provide clear rationale for productive direction

**Confidence delta**: `0.0` (no direct confidence impact - advisory only)

**Reasoning frequency**: Conditional (when stagnation detected after cycle 5+)

**Response fields**:
- `suggested_direction` (string): Vector or description of direction in embedding space
- `target_region` (string): Description of underexplored region to explore
- `exploration_rationale` (string): Why this direction is productive, what new territory it opens
- `valid` (boolean): Whether response was properly formatted

---

### Perturber

**Skill**: Inject frontier ideas into debate

**Expertise**: Frontier idea selection and pivot claim generation

**Logical constraints**:
- Scheduled with 20% probability per cycle
- Selects eligible frontier idea from pool (2+ sponsors, not activated)
- Uses weighted selection: more sponsors + younger = higher weight
- Must use frontier idea to generate NEW claim that pivots debate
- Pivot must be direct extension or consequence of frontier idea
- Must explain how pivot connects to previous debate direction
- Must provide clear rationale for strategic value

**Confidence delta**: `0.0` (creates new claim starting at 0.5 support, no delta applied)

**Reasoning frequency**: 20% probability per cycle (when eligible frontier exists)

**Response fields**:
- `pivot_claim` (string): New claim derived from frontier idea
- `connection_to_previous` (string): Explanation of pivot's relation to previous debate
- `pivot_rationale` (string): Why pivot is strategically valuable
- `activated` (boolean): Whether perturber was activated (false if no frontier or skip)
- `valid` (boolean): Whether response was properly formatted

---

## Special Agent

### Summarizer

**Skill**: Generate context summaries that resolve implicit references in claims

**Expertise**: Context window management and reference resolution

**Logical constraints**:
- Uses sliding context window approach (last 5 cycles)
- Receives: current claim, last 5 cycles of claim history, last 5 cycles of agent contributions
- Uses summary from 5 cycles ago as foundational context
- Must identify all implicit references (pronouns, vague terms like "their", "it", "they", "the result", "the conclusion")
- Must resolve each implicit reference by making it explicit based on previous summary and recent history
- Must generate full_context_summary: claim rewritten with all implicit references explicit
- Must generate evolution_narrative: 2-3 sentence summary of claim's evolution
- Must list addressed_objections: objections that have been addressed
- Must list remaining_gaps: ambiguities that still exist
- Forbidden: Transitional opening words in full_context_summary ("Therefore", "Consequently", "Thus", etc.)
- Must be complete standalone claim needing no additional context

**Confidence delta**: N/A (not part of confidence system - generates context only)

**Reasoning frequency**: Runs independently, not scheduled by cycle

**Response fields** (stored as ClaimSummary):
- `full_context_summary` (string): Claim with all implicit references made explicit
- `evolution_narrative` (string): 2-3 sentence explanation of claim's evolution
- `addressed_objections` (map): Objections that have been addressed
- `remaining_gaps` (map): Ambiguities or unresolved issues

---

## Agent Registry

All agents are registered in `lib/unshackled/cycle/scheduler.ex` and validated in `lib/unshackled/agents/agent_contribution.ex`:

```elixir
@valid_agent_roles ~w[
  explorer
  critic
  connector
  steelman
  operationalizer
  quantifier
  reducer
  boundary_hunter
  translator
  historian
  grave_keeper
  cartographer
  perturber
]
```

## Implementation Pattern

All agents implement the `Unshackled.Agents.Agent` behaviour:

```elixir
@callback role() :: atom()
@callback build_prompt(Server.t()) :: String.t()
@callback parse_response(String.t()) :: map()
@callback confidence_delta(map()) :: float()
```

Each agent returns a map with:
- Agent-specific fields for the response content
- `valid`: Boolean indicating if response was properly formatted
- `error`: Error message if invalid (optional)

## Confidence Dynamics

Claims evolve through agent interactions with:
- Birth support: `0.5`
- Death threshold: `0.2`
- Graduation threshold: `0.85`
- Per-cycle decay: `-0.02`
- Floor: `0.2`, Ceiling: `0.9`

Positive deltas increase confidence (Explorer, Connector, Quantifier).
Negative deltas decrease confidence (Critic, Steelman, Boundary Hunter).
Advisory agents provide guidance without direct confidence impact (Reducer, Translator, Historian, Grave Keeper, Cartographer, Operationalizer).
Perturber creates new claims (no delta to existing support).
Summarizer provides context (outside confidence system).

## Further Reading

- Agent behaviour: `lib/unshackled/agents/agent.ex`
- Scheduler: `lib/unshackled/cycle/scheduler.ex`
- Contribution schema: `lib/unshackled/agents/agent_contribution.ex`
- Blackboard: `lib/unshackled/blackboard/server.ex`
