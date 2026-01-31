defmodule Unshackled.ConfigHelpersTest do
  use ExUnit.Case, async: true

  describe "defconfig/2" do
    setup do
      on_exit(fn ->
        Application.delete_env(:unshackled, :test_config)
      end)
    end

    test "generates getter function that returns default when not configured" do
      defmodule TestConfigDefault do
        import Unshackled.ConfigHelpers

        defconfig(:test_value, app_key: :test_config, default: "default_value")
      end

      assert TestConfigDefault.test_value() == "default_value"
    end

    test "generates getter function that returns configured value when set" do
      defmodule TestConfigValue do
        import Unshackled.ConfigHelpers

        defconfig(:test_value, app_key: :test_config, default: "default_value")
      end

      Application.put_env(:unshackled, :test_config, test_value: "configured_value")

      assert TestConfigValue.test_value() == "configured_value"

      Application.put_env(:unshackled, :test_config, [])
    end

    test "generates function with float default" do
      defmodule TestConfigFloat do
        import Unshackled.ConfigHelpers

        defconfig(:similarity_threshold, app_key: :test_config, default: 0.95)
      end

      assert TestConfigFloat.similarity_threshold() == 0.95

      Application.put_env(:unshackled, :test_config, similarity_threshold: 0.85)

      assert TestConfigFloat.similarity_threshold() == 0.85

      Application.put_env(:unshackled, :test_config, [])
    end

    test "generates function with integer default" do
      defmodule TestConfigInt do
        import Unshackled.ConfigHelpers

        defconfig(:debounce_cycles, app_key: :test_config, default: 5)
      end

      assert TestConfigInt.debounce_cycles() == 5

      Application.put_env(:unshackled, :test_config, debounce_cycles: 10)

      assert TestConfigInt.debounce_cycles() == 10

      Application.put_env(:unshackled, :test_config, [])
    end

    test "generates function with atom default" do
      defmodule TestConfigAtom do
        import Unshackled.ConfigHelpers

        defconfig(:cycle_mode, app_key: :test_config, default: :event_driven)
      end

      assert TestConfigAtom.cycle_mode() == :event_driven

      Application.put_env(:unshackled, :test_config, cycle_mode: :time_based)

      assert TestConfigAtom.cycle_mode() == :time_based

      Application.put_env(:unshackled, :test_config, [])
    end

    test "generates function with list default" do
      defmodule TestConfigList do
        import Unshackled.ConfigHelpers

        defconfig(:models, app_key: :test_config, default: ["model1", "model2"])
      end

      assert TestConfigList.models() == ["model1", "model2"]

      Application.put_env(:unshackled, :test_config, models: ["model3", "model4"])

      assert TestConfigList.models() == ["model3", "model4"]

      Application.put_env(:unshackled, :test_config, [])
    end

    test "handles missing app env gracefully" do
      defmodule TestConfigMissingEnv do
        import Unshackled.ConfigHelpers

        defconfig(:some_value, app_key: :nonexistent_key, default: "default")
      end

      Application.delete_env(:unshackled, :nonexistent_key)

      assert TestConfigMissingEnv.some_value() == "default"
    end

    test "partial config returns defaults for missing keys" do
      defmodule TestConfigPartial do
        import Unshackled.ConfigHelpers

        defconfig(:value1, app_key: :test_config, default: "default1")
        defconfig(:value2, app_key: :test_config, default: "default2")
      end

      Application.put_env(:unshackled, :test_config, value1: "configured1")

      assert TestConfigPartial.value1() == "configured1"
      assert TestConfigPartial.value2() == "default2"

      Application.put_env(:unshackled, :test_config, [])
    end

    test "generated function is equivalent to handwritten version" do
      defmodule TestConfigHandwritten do
        @default_value 0.95

        def handwritten do
          Keyword.get(
            Application.get_env(:unshackled, :test_config, []),
            :handwritten,
            @default_value
          )
        end
      end

      defmodule TestConfigGenerated do
        import Unshackled.ConfigHelpers

        defconfig(:generated, app_key: :test_config, default: 0.95)
      end

      assert TestConfigGenerated.generated() == TestConfigHandwritten.handwritten()

      Application.put_env(:unshackled, :test_config, handwritten: 0.85, generated: 0.85)

      assert TestConfigGenerated.generated() == TestConfigHandwritten.handwritten()

      Application.put_env(:unshackled, :test_config, [])
    end
  end

  describe "negative cases" do
    test "raises compile error when :app_key is missing" do
      assert_raise KeyError, ~r/key :app_key not found/, fn ->
        Code.compile_string("""
          defmodule TestConfigMissingAppKey do
            import Unshackled.ConfigHelpers

            defconfig :test_value, default: "default"
          end
        """)
      end
    end

    test "raises compile error when :default is missing" do
      assert_raise KeyError, ~r/key :default not found/, fn ->
        Code.compile_string("""
          defmodule TestConfigMissingDefault do
            import Unshackled.ConfigHelpers

            defconfig :test_value, app_key: :test_config
          end
        """)
      end
    end

    test "raises compile error when both required options are missing" do
      assert_raise KeyError, ~r/key :app_key not found/, fn ->
        Code.compile_string("""
          defmodule TestConfigMissingBoth do
            import Unshackled.ConfigHelpers

            defconfig :test_value, []
          end
        """)
      end
    end
  end
end
