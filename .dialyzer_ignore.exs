[
  # Pattern match guard clauses - acceptable for defensive coding
  ~r/lib\/unshackled\/agents\/connector.ex.*pattern_match_cov/,
  ~r/lib\/unshackled\/agents\/operationalizer.ex.*pattern_match_cov/,
  ~r/lib\/unshackled\/cycle\/runner.ex.*pattern_match_cov/,
  ~r/lib\/unshackled\/cycle\/runner.ex.*pattern_match/,

  # Comparison checks - valid defensive coding
  ~r/lib\/unshackled\/cycle\/runner.ex.*exact_compare/,

  # Call success warnings - function calls with error handling
  ~r/lib\/unshackled\/blackboard\/server.ex.*:call/,

  # Invalid contracts - Nx library type inference issues
  ~r/lib\/unshackled\/embedding\/space.ex.*invalid_contract/,
  ~r/lib\/unshackled\/embedding\/similarity.ex.*invalid_contract/,
  ~r/lib\/unshackled\/visualization\/trajectory.ex.*invalid_contract/,

  # Unknown types - Ecto schema types
  ~r/lib\/unshackled\/embedding\/similarity.ex.*unknown_type/,

  # Nx library pattern match issues - eigh returns tuple at runtime
  ~r/lib\/unshackled\/visualization\/trajectory.ex.*pattern_match/,

  # Unused functions in trajectory visualization - dialyzer incorrectly infers unreachable code
  # due to Nx library type issues, but these functions are called at runtime
  ~r/lib\/unshackled\/visualization\/trajectory.ex.*unused_fun/
]
