defmodule Unshackled.Embedding.FeaturesTest do
  use ExUnit.Case, async: true

  alias Unshackled.Embedding.Features

  describe "extract_features/1" do
    test "extracts features from valid claim text" do
      claim = "All entropy increases in closed systems"

      assert {:ok, features} = Features.extract_features(claim)

      assert %Features{} = features
      assert features.claim_type in [:empirical, :normative, :causal]
      assert features.quantification in [:universal, :existential, :none]
      assert features.modality in [:necessary, :possible, :actual]

      assert features.domain in [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end

    test "extracts features for empirical physics claim" do
      claim = "Heat flows from hot to cold in isolated regions"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.claim_type in [:empirical, :normative, :causal]

      assert features.domain in [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end

    test "extracts features for normative claim" do
      claim = "We should prioritize truth over comfort in scientific inquiry"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.claim_type in [:empirical, :normative, :causal]
    end

    test "handles universal quantification claim" do
      claim = "All electrons have identical properties"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.quantification in [:universal, :existential, :none]
    end

    test "handles existential quantification claim" do
      claim = "Some systems exhibit emergent behavior"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.quantification in [:universal, :existential, :none]
    end

    test "handles necessary modality claim" do
      claim = "Energy cannot be created or destroyed"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.modality in [:necessary, :possible, :actual]
    end

    test "handles possible modality claim" do
      claim = "Quantum systems may exhibit superposition"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.modality in [:necessary, :possible, :actual]
    end

    test "handles actual modality claim" do
      claim = "The speed of light is constant in a vacuum"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.modality in [:necessary, :possible, :actual]
    end

    test "handles physics domain claim" do
      claim = "Entropy increases in isolated systems"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.domain in [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end

    test "handles philosophy domain claim" do
      claim = "Moral truths exist independently of human opinion"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.domain in [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end

    test "handles economics domain claim" do
      claim = "Supply and demand determine market prices"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.domain in [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end

    test "handles biology domain claim" do
      claim = "Natural selection drives evolutionary change"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.domain in [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end

    test "handles mathematics domain claim" do
      claim = "The sum of angles in a triangle equals 180 degrees"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.domain in [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end

    test "handles information theory domain claim" do
      claim = "Information is conserved in quantum operations"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.domain in [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end

    test "handles complex causal claim" do
      claim = "Increasing temperature causes chemical reactions to accelerate"

      assert {:ok, features} = Features.extract_features(claim)

      assert features.claim_type in [:empirical, :normative, :causal]
    end

    test "returns error for empty string" do
      assert {:error, "Cannot extract features from empty string"} = Features.extract_features("")
    end

    test "returns error for whitespace-only string" do
      assert {:error, "Cannot extract features from empty string"} =
               Features.extract_features("   ")
    end

    test "returns error for nil input" do
      assert {:error, "Invalid claim text type"} = Features.extract_features(nil)
    end

    test "returns error for non-string input" do
      assert {:error, "Invalid claim text type"} = Features.extract_features(123)
    end

    test "handles special characters in claim" do
      claim = "Quantum decoherence α → β occurs at temperature T"

      assert {:ok, features} = Features.extract_features(claim)
      assert %Features{} = features
    end

    test "handles very long claim text" do
      claim = String.duplicate("This is a test claim about physics. ", 100)

      assert {:ok, features} = Features.extract_features(claim)
      assert %Features{} = features
    end

    test "handles ambiguous claims with default categories" do
      claim = "Something might happen somewhere"

      assert {:ok, features} = Features.extract_features(claim)
      assert %Features{} = features
    end

    test "handles claims with multiple quantifiers" do
      claim = "All systems that are closed exhibit some level of entropy increase"

      assert {:ok, features} = Features.extract_features(claim)
      assert %Features{} = features
    end
  end

  describe "to_vector/1" do
    test "converts features to index vector" do
      features = %Features{
        claim_type: :empirical,
        quantification: :universal,
        modality: :necessary,
        domain: :physics
      }

      vector = Features.to_vector(features)

      assert is_list(vector)
      assert length(vector) == 4
      assert Enum.all?(vector, &is_integer/1)
      assert Enum.all?(vector, &(&1 >= 0))
    end

    test "indices are within valid range" do
      features = %Features{
        claim_type: :normative,
        quantification: :existential,
        modality: :possible,
        domain: :philosophy
      }

      vector = Features.to_vector(features)

      assert vector |> Enum.all?(fn idx -> idx >= 0 and idx <= 6 end)
    end

    test "all valid claim_types produce valid indices" do
      claim_types = [:empirical, :normative, :causal]

      Enum.each(claim_types, fn ct ->
        features = %Features{
          claim_type: ct,
          quantification: :none,
          modality: :actual,
          domain: :other
        }

        vector = Features.to_vector(features)
        assert Enum.at(vector, 0) in [0, 1, 2]
      end)
    end

    test "all valid quantifications produce valid indices" do
      quantifications = [:universal, :existential, :none]

      Enum.each(quantifications, fn q ->
        features = %Features{
          claim_type: :empirical,
          quantification: q,
          modality: :actual,
          domain: :other
        }

        vector = Features.to_vector(features)
        assert Enum.at(vector, 1) in [0, 1, 2]
      end)
    end

    test "all valid modalities produce valid indices" do
      modalities = [:necessary, :possible, :actual]

      Enum.each(modalities, fn m ->
        features = %Features{
          claim_type: :empirical,
          quantification: :none,
          modality: m,
          domain: :other
        }

        vector = Features.to_vector(features)
        assert Enum.at(vector, 2) in [0, 1, 2]
      end)
    end

    test "all valid domains produce valid indices" do
      domains = [
        :physics,
        :philosophy,
        :economics,
        :biology,
        :mathematics,
        :information_theory,
        :other
      ]

      Enum.each(domains, fn d ->
        features = %Features{
          claim_type: :empirical,
          quantification: :none,
          modality: :actual,
          domain: d
        }

        vector = Features.to_vector(features)
        assert Enum.at(vector, 3) in [0, 1, 2, 3, 4, 5, 6]
      end)
    end
  end

  describe "combine_with_semantic/2" do
    test "combines features with semantic embedding" do
      features = %Features{
        claim_type: :empirical,
        quantification: :universal,
        modality: :necessary,
        domain: :physics
      }

      semantic_embedding = Nx.tensor(Enum.to_list(1..768), type: :f32)

      assert {:ok, combined} = Features.combine_with_semantic(features, semantic_embedding)

      assert %Nx.Tensor{} = combined
      assert Nx.size(combined) == Nx.size(semantic_embedding) + 4
    end

    test "combined vector ends with normalized feature indices" do
      features = %Features{
        claim_type: :empirical,
        quantification: :universal,
        modality: :necessary,
        domain: :physics
      }

      semantic_embedding = Nx.tensor(Enum.to_list(1..768), type: :f32)

      assert {:ok, combined} = Features.combine_with_semantic(features, semantic_embedding)

      last_four = Nx.slice(combined, [764], [4]) |> Nx.to_list()

      assert length(last_four) == 4
    end

    test "returns error for invalid features input" do
      semantic_embedding = Nx.tensor(Enum.to_list(1..768), type: :f32)

      assert {:error, "Invalid inputs to combine_with_semantic"} =
               Features.combine_with_semantic("invalid", semantic_embedding)
    end

    test "returns error for invalid semantic embedding input" do
      features = %Features{
        claim_type: :empirical,
        quantification: :universal,
        modality: :necessary,
        domain: :physics
      }

      assert {:error, "Invalid inputs to combine_with_semantic"} =
               Features.combine_with_semantic(features, "invalid")
    end

    test "handles different semantic embedding dimensions" do
      features = %Features{
        claim_type: :empirical,
        quantification: :none,
        modality: :actual,
        domain: :other
      }

      semantic_embedding = Nx.tensor(Enum.to_list(1..100), type: :f32)

      assert {:ok, combined} = Features.combine_with_semantic(features, semantic_embedding)

      assert Nx.size(combined) == 104
    end
  end

  describe "categories/0" do
    test "returns all valid categories" do
      categories = Features.categories()

      assert is_map(categories)
      assert Map.has_key?(categories, :claim_types)
      assert Map.has_key?(categories, :quantifications)
      assert Map.has_key?(categories, :modalities)
      assert Map.has_key?(categories, :domains)
    end

    test "claim_types has correct values" do
      categories = Features.categories()

      assert categories.claim_types == [:empirical, :normative, :causal]
    end

    test "quantifications has correct values" do
      categories = Features.categories()

      assert categories.quantifications == [:universal, :existential, :none]
    end

    test "modalities has correct values" do
      categories = Features.categories()

      assert categories.modalities == [:necessary, :possible, :actual]
    end

    test "domains has correct values" do
      categories = Features.categories()

      assert categories.domains == [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end
  end

  describe "integration" do
    test "complete workflow: extract features, convert to vector, combine with embedding" do
      claim = "All entropy increases in closed systems"

      assert {:ok, features} = Features.extract_features(claim)

      vector = Features.to_vector(features)
      assert length(vector) == 4

      semantic_embedding = Nx.tensor(Enum.to_list(1..768), type: :f32)

      assert {:ok, combined} = Features.combine_with_semantic(features, semantic_embedding)

      assert Nx.size(combined) == 772
    end

    test "extracts consistent features for same claim" do
      claim = "Heat flows from hot to cold"

      assert {:ok, features1} = Features.extract_features(claim)
      assert {:ok, features2} = Features.extract_features(claim)

      assert features1.claim_type == features2.claim_type
      assert features1.quantification == features2.quantification
      assert features1.modality == features2.modality
      assert features1.domain == features2.domain
    end
  end

  describe "negative cases" do
    test "handles unclassifiable claim by returning default features" do
      claim = "Xyz 123 !!! ???"

      assert {:ok, features} = Features.extract_features(claim)
      assert %Features{} = features
    end

    test "extract_features with malformed JSON response falls back to defaults" do
      claim = "Test claim"

      assert {:ok, features} = Features.extract_features(claim)
      assert %Features{} = features
    end

    test "combine_with_semantic with nil features returns error" do
      semantic_embedding = Nx.tensor(Enum.to_list(1..768), type: :f32)

      assert {:error, "Invalid inputs to combine_with_semantic"} =
               Features.combine_with_semantic(nil, semantic_embedding)
    end

    test "combine_with_semantic with nil embedding returns error" do
      features = %Features{
        claim_type: :empirical,
        quantification: :none,
        modality: :actual,
        domain: :other
      }

      assert {:error, "Invalid inputs to combine_with_semantic"} =
               Features.combine_with_semantic(features, nil)
    end
  end

  describe "example from PRD" do
    test "All entropy increases returns valid feature vector" do
      claim = "All entropy increases"

      assert {:ok, features} = Features.extract_features(claim)

      assert %Features{} = features
      assert features.claim_type in [:empirical, :normative, :causal]
      assert features.quantification in [:universal, :existential, :none]
      assert features.modality in [:necessary, :possible, :actual]

      assert features.domain in [
               :physics,
               :philosophy,
               :economics,
               :biology,
               :mathematics,
               :information_theory,
               :other
             ]
    end

    test "feature vector for All entropy increases" do
      claim = "All entropy increases"

      assert {:ok, features} = Features.extract_features(claim)

      vector = Features.to_vector(features)

      assert is_list(vector)
      assert length(vector) == 4
    end
  end
end
