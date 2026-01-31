defmodule UnshackledWeb.CoreComponents do
  @moduledoc """
  Provides core UI components for the Unshackled web interface.

  Design System: Refined Brutalist
  - Sharp edges, high contrast
  - JetBrains Mono for display/data, Inter for body
  - Subtle depth through gradients and shadows
  - Polished animations and micro-interactions
  """
  use Phoenix.Component

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash messages.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome!</.flash>
  """
  attr(:id, :string, doc: "the optional id of flash container")
  attr(:flash, :map, default: %{}, doc: "the map of flash messages to display")
  attr(:title, :string, default: nil)
  attr(:kind, :atom, values: [:info, :error], doc: "used for styling and aria attributes")
  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")

  slot(:inner_block, doc: "the optional inner block that renders the flash message")

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-hook={@kind == :info && "FlashHook"}
      role="alert"
      class={[
        "w-80 p-4 border animate-slide-in-left shadow-medium relative",
        @kind == :info && "bg-surface border-status-graduated/50 text-text-primary",
        @kind == :error && "bg-surface border-status-dead/50 text-text-primary"
      ]}
      {@rest}
    >
      <%!-- Accent stripe --%>
      <div class={[
        "absolute left-0 top-0 bottom-0 w-1",
        @kind == :info && "bg-status-graduated",
        @kind == :error && "bg-status-dead"
      ]}></div>

      <div class="pl-3">
        <p :if={@title} class="flex items-center gap-2 font-display text-xs font-semibold uppercase tracking-wider">
          <span :if={@kind == :info} class="text-status-graduated">INFO</span>
          <span :if={@kind == :error} class="text-status-dead">ERROR</span>
        </p>
        <p class="mt-1.5 text-sm text-text-secondary font-body leading-relaxed"><%= msg %></p>
      </div>

      <button
        type="button"
        class="group absolute top-3 right-3 p-1 hover:bg-surface-elevated transition-colors"
        aria-label="close"
      >
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-3.5 h-3.5 text-text-muted group-hover:text-text-primary transition-colors">
          <path d="M5.28 4.22a.75.75 0 0 0-1.06 1.06L6.94 8l-2.72 2.72a.75.75 0 1 0 1.06 1.06L8 9.06l2.72 2.72a.75.75 0 1 0 1.06-1.06L9.06 8l2.72-2.72a.75.75 0 0 0-1.06-1.06L8 6.94 5.28 4.22Z" />
        </svg>
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard dismissable flash messages.
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="fixed bottom-4 left-4 z-50 flex flex-col gap-2 pointer-events-none">
      <div class="pointer-events-auto">
        <.flash kind={:info} title="Success" flash={@flash} />
      </div>
      <div class="pointer-events-auto">
        <.flash kind={:error} title="Error" flash={@flash} />
      </div>
      <div class="pointer-events-auto">
        <.flash
          id="client-error"
          kind={:error}
          title="Connection Lost"
          phx-disconnected={show(".phx-client-error #client-error")}
          phx-connected={hide("#client-error")}
          hidden
        >
          Attempting to reconnect...
        </.flash>
      </div>
      <div class="pointer-events-auto">
        <.flash
          id="server-error"
          kind={:error}
          title="Server Error"
          phx-disconnected={show(".phx-server-error #server-error")}
          phx-connected={hide("#server-error")}
          hidden
        >
          Hang in there while we get back on track.
        </.flash>
      </div>
    </div>
    """
  end

  @doc """
  Renders a status badge with color variants.

  ## Examples

      <.status_badge status={:active} />
      <.status_badge status={:paused} />
      <.status_badge status={:dead} />
      <.status_badge status={:graduated} />
  """
  attr(:status, :atom,
    required: true,
    values: [:active, :paused, :dead, :graduated, :stopped, :running, :completed],
    doc: "the status to display"
  )

  attr(:class, :string, default: nil, doc: "additional CSS classes")

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2.5 py-1 font-display text-[0.625rem] font-semibold uppercase tracking-wider border",
      status_classes(@status),
      @status in [:active, :running] && "badge-running",
      @class
    ]}>
      <%!-- Status dot for running states --%>
      <span :if={@status in [:active, :running]} class="relative flex h-1.5 w-1.5">
        <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-current opacity-75"></span>
        <span class="relative inline-flex rounded-full h-1.5 w-1.5 bg-current"></span>
      </span>
      <%= status_text(@status) %>
    </span>
    """
  end

  defp status_classes(:active),
    do: "bg-status-active/10 text-status-active border-status-active/40"

  defp status_classes(:running),
    do: "bg-status-active/10 text-status-active border-status-active/40"

  defp status_classes(:paused),
    do: "bg-status-paused/10 text-status-paused border-status-paused/40"

  defp status_classes(:dead), do: "bg-status-dead/10 text-status-dead border-status-dead/40"
  defp status_classes(:stopped), do: "bg-status-dead/10 text-status-dead border-status-dead/40"

  defp status_classes(:graduated),
    do: "bg-status-graduated/10 text-status-graduated border-status-graduated/40"

  defp status_classes(:completed),
    do: "bg-status-graduated/10 text-status-graduated border-status-graduated/40"

  defp status_text(:active), do: "Active"
  defp status_text(:running), do: "Running"
  defp status_text(:paused), do: "Paused"
  defp status_text(:dead), do: "Dead"
  defp status_text(:stopped), do: "Stopped"
  defp status_text(:graduated), do: "Graduated"
  defp status_text(:completed), do: "Completed"

  @doc """
  Renders a button with brutalist styling.

  ## Examples

      <.button>Send</.button>
      <.button phx-click="go" variant={:primary}>Send</.button>
      <.button variant={:danger}>Delete</.button>
  """
  attr(:type, :string, default: nil)
  attr(:variant, :atom, default: :primary, values: [:primary, :secondary, :danger])
  attr(:class, :string, default: nil)
  attr(:rest, :global, include: ~w(disabled form name value))

  slot(:inner_block, required: true)

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "btn px-5 py-2.5 font-display text-xs font-semibold uppercase tracking-wider border-2",
        "disabled:opacity-40 disabled:cursor-not-allowed disabled:transform-none",
        variant_classes(@variant),
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  defp variant_classes(:primary) do
    "btn-primary bg-accent text-background border-accent hover:bg-accent-bright hover:border-accent-bright"
  end

  defp variant_classes(:secondary) do
    "bg-transparent text-text-primary border-border hover:bg-surface-elevated hover:border-accent hover:text-accent"
  end

  defp variant_classes(:danger) do
    "bg-status-dead/10 text-status-dead border-status-dead/50 hover:bg-status-dead hover:text-background hover:border-status-dead"
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr(:for, :any, required: true, doc: "the data structure for the form")
  attr(:as, :any, default: nil, doc: "the server side parameter to collect all input under")

  attr(:rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"
  )

  slot(:inner_block, required: true)
  slot(:actions, doc: "the slot for form actions, such as a submit button")

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="space-y-6">
        <%= render_slot(@inner_block, f) %>
        <div :for={action <- @actions} class="mt-6 flex items-center justify-end gap-4">
          <%= render_slot(action, f) %>
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders an input with label and error messages.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any)

  attr(:type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week)
  )

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"
  )

  attr(:errors, :list, default: [])
  attr(:checked, :boolean, doc: "the checked flag for checkbox inputs")
  attr(:prompt, :string, default: nil, doc: "the prompt for select inputs")
  attr(:options, :list, doc: "the options to pass to Form.options_for_select/2")
  attr(:multiple, :boolean, default: false, doc: "the multiple flag for select inputs")

  attr(:rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)
  )

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <label class="group flex items-center gap-3 cursor-pointer py-1">
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
      <div class="relative">
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="peer sr-only"
          {@rest}
        />
        <div class="h-5 w-5 border border-border bg-surface peer-checked:bg-accent peer-checked:border-accent peer-focus-visible:ring-2 peer-focus-visible:ring-accent peer-focus-visible:ring-offset-2 peer-focus-visible:ring-offset-background transition-all">
          <svg class="h-5 w-5 text-background opacity-0 peer-checked:opacity-100 transition-opacity" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd" />
          </svg>
        </div>
      </div>
      <span class="text-text-secondary text-sm font-body group-hover:text-text-primary transition-colors"><%= @label %></span>
    </label>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id} class="block font-display text-xs font-semibold uppercase tracking-wider text-text-secondary mb-2">
        <%= @label %>
      </label>
      <select
        id={@id}
        name={@name}
        class="block w-full bg-surface border border-border px-3 py-2.5 text-text-primary font-body text-sm focus-accent hover:border-border-strong transition-colors"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Form.options_for_select(@options, @value) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id} class="block font-display text-xs font-semibold uppercase tracking-wider text-text-secondary mb-2">
        <%= @label %>
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "block w-full bg-surface border border-border px-4 py-3 text-text-primary font-body",
          "placeholder:text-text-muted focus-accent min-h-[100px] hover:border-border-strong transition-colors",
          @errors != [] && "border-status-dead"
        ]}
        {@rest}
      ><%= Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div>
      <label :if={@label} for={@id} class="block font-display text-xs font-semibold uppercase tracking-wider text-text-secondary mb-2">
        <%= @label %>
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={[
          "block w-full bg-surface border border-border px-3 py-2.5 text-text-primary font-body text-sm",
          "placeholder:text-text-muted focus-accent hover:border-border-strong transition-colors",
          @errors != [] && "border-status-dead"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Renders an error message.
  """
  slot(:inner_block, required: true)

  def error(assigns) do
    ~H"""
    <p class="mt-2 flex items-center gap-1.5 text-xs text-status-dead font-body">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-3.5 h-3.5 flex-shrink-0">
        <path fill-rule="evenodd" d="M8 15A7 7 0 1 0 8 1a7 7 0 0 0 0 14ZM8 4a.75.75 0 0 1 .75.75v3a.75.75 0 0 1-1.5 0v-3A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clip-rule="evenodd" />
      </svg>
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr(:class, :string, default: nil)

  slot(:inner_block, required: true)
  slot(:subtitle)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class={["mb-8", @class]}>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="font-display text-2xl font-bold tracking-tight text-text-primary">
            <%= render_slot(@inner_block) %>
          </h1>
          <p :if={@subtitle != []} class="mt-1.5 text-sm text-text-secondary font-body">
            <%= render_slot(@subtitle) %>
          </p>
        </div>
        <div :if={@actions != []} class="flex gap-3">
          <%= render_slot(@actions) %>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Renders a data list with label-value pairs.

  ## Examples

      <.list>
        <:item title="Cycle">42</:item>
        <:item title="Support">0.75</:item>
      </.list>
  """
  slot :item, required: true do
    attr(:title, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <dl class="divide-y divide-border">
      <div :for={item <- @item} class="py-3 flex justify-between gap-4">
        <dt class="text-sm font-medium text-text-secondary"><%= item.title %></dt>
        <dd class="text-sm text-text-primary font-mono-data"><%= render_slot(item) %></dd>
      </div>
    </dl>
    """
  end

  @doc """
  Renders a card container.
  """
  attr(:class, :string, default: nil)
  attr(:shadow, :boolean, default: false, doc: "add neo-brutalist offset shadow")
  attr(:interactive, :boolean, default: false, doc: "add hover lift effect")
  attr(:accent, :boolean, default: false, doc: "add accent left border")
  slot(:inner_block, required: true)

  def card(assigns) do
    ~H"""
    <div class={[
      "bg-surface border-2 border-border p-6 relative",
      @shadow && "shadow-subtle",
      @interactive && "card-interactive cursor-pointer",
      @accent && "accent-stripe",
      @class
    ]}>
      <%!-- Subtle top gradient for depth --%>
      <div class="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-white/5 to-transparent"></div>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Renders a D3 chart container with LiveView hook integration.

  The chart receives data via the `data` attribute, which is JSON-encoded
  and passed to the JavaScript hook via `data-chart-data`.

  ## Examples

      <.chart id="support-timeline" hook="ChartHook" data={@timeline_data} />
      <.chart id="trajectory" hook="TrajectoryPlotHook" data={@trajectory_data} height={300} />
  """
  attr(:id, :string, required: true, doc: "unique identifier for the chart element")
  attr(:hook, :string, default: "ChartHook", doc: "the LiveView hook to use for rendering")
  attr(:data, :any, default: [], doc: "chart data to be JSON-encoded and passed to the hook")
  attr(:width, :integer, default: nil, doc: "chart width in pixels (defaults to container width)")
  attr(:height, :integer, default: 200, doc: "chart height in pixels")
  attr(:class, :string, default: nil, doc: "additional CSS classes")

  attr(:margin_top, :integer, default: 20)
  attr(:margin_right, :integer, default: 20)
  attr(:margin_bottom, :integer, default: 30)
  attr(:margin_left, :integer, default: 40)

  def chart(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook={@hook}
      data-chart-data={Jason.encode!(@data)}
      data-chart-height={@height}
      data-chart-width={@width}
      data-chart-margin-top={@margin_top}
      data-chart-margin-right={@margin_right}
      data-chart-margin-bottom={@margin_bottom}
      data-chart-margin-left={@margin_left}
      class={["chart-container bg-surface border border-border p-6", @class]}
    >
    </div>
    """
  end

  @doc """
  Renders a collapsible section with a header that toggles visibility.

  ## Examples

      <.collapsible id="cemetery" title="Cemetery" count={3}>
        <p>Collapsed content here</p>
      </.collapsible>
  """
  attr(:id, :string, required: true, doc: "unique identifier for the section")
  attr(:title, :string, required: true, doc: "section header title")
  attr(:count, :integer, default: nil, doc: "optional badge count shown in header")
  attr(:open, :boolean, default: false, doc: "whether the section starts expanded")
  attr(:class, :string, default: nil, doc: "additional CSS classes for the container")
  attr(:header_class, :string, default: nil, doc: "additional CSS classes for the header")

  slot(:inner_block, required: true)

  def collapsible(assigns) do
    ~H"""
    <div id={@id} class={["border-2 border-border bg-surface", @class]}>
      <button
        type="button"
        phx-click={toggle_collapsible("##{@id}-content")}
        class={[
          "w-full flex items-center justify-between p-4 text-left",
          "hover:bg-surface-elevated transition-colors",
          @header_class
        ]}
        aria-expanded={@open}
        aria-controls={"#{@id}-content"}
      >
        <span class="flex items-center gap-3">
          <span class="text-lg font-bold text-text-primary uppercase tracking-wider">
            <%= @title %>
          </span>
          <span
            :if={@count && @count > 0}
            class="inline-flex items-center px-2 py-0.5 text-xs font-bold text-text-muted border border-border"
          >
            <%= @count %>
          </span>
        </span>
        <span id={"#{@id}-indicator"} class="text-text-muted font-mono text-lg">
          <%= if @open, do: "−", else: "+" %>
        </span>
      </button>
      <div
        id={"#{@id}-content"}
        class="px-4 pb-4"
        style={if @open, do: "", else: "display: none;"}
      >
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  defp toggle_collapsible(selector) do
    %JS{}
    |> JS.toggle(
      to: selector,
      time: 0,
      in: {"", "", ""},
      out: {"", "", ""}
    )
    |> JS.dispatch("phx:toggle-indicator", to: selector)
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 0,
      transition: {"", "", ""}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 0,
      transition: {"", "", ""}
    )
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Renders a loading spinner with brutalist styling.

  ## Examples

      <.spinner />
      <.spinner size={:lg} />
      <.spinner label="Starting session..." />
  """
  attr(:size, :atom, default: :md, values: [:sm, :md, :lg], doc: "spinner size")
  attr(:label, :string, default: nil, doc: "optional label shown below spinner")
  attr(:class, :string, default: nil, doc: "additional CSS classes")

  def spinner(assigns) do
    ~H"""
    <div class={["flex flex-col items-center justify-center gap-3", @class]}>
      <div class={[
        "border-2 border-border border-t-accent animate-spin",
        spinner_size(@size)
      ]}>
      </div>
      <span :if={@label} class="text-text-muted text-xs font-display uppercase tracking-wider">
        <%= @label %>
      </span>
    </div>
    """
  end

  defp spinner_size(:sm), do: "w-4 h-4"
  defp spinner_size(:md), do: "w-6 h-6"
  defp spinner_size(:lg), do: "w-8 h-8"

  @doc """
  Renders a skeleton loading placeholder.

  Skeletons show placeholder content while data loads, providing visual feedback
  that the application is working.

  ## Examples

      <.skeleton class="h-8 w-32" />
      <.skeleton class="h-4 w-full" />
  """
  attr(:class, :string, default: "", doc: "CSS classes for sizing (height, width, etc.)")

  @spec skeleton(map()) :: Phoenix.LiveView.Rendered.t()

  def skeleton(assigns) do
    ~H"""
    <div class={["skeleton-shimmer", @class]}></div>
    """
  end

  @doc """
  Renders a skeleton card placeholder for full card loading states.

  ## Examples

      <.skeleton_card />
  """
  attr(:class, :string, default: nil, doc: "additional CSS classes")

  @spec skeleton_card(map()) :: Phoenix.LiveView.Rendered.t()

  def skeleton_card(assigns) do
    ~H"""
    <div class={["skeleton-shimmer h-32 w-full border-2 border-border", @class]}></div>
    """
  end

  @doc """
  Renders a loading overlay for async operations.

  ## Examples

      <.loading_overlay :if={@loading} message="Starting session..." />
  """
  attr(:message, :string, default: "Loading...", doc: "message shown during loading")
  attr(:class, :string, default: nil, doc: "additional CSS classes")

  def loading_overlay(assigns) do
    ~H"""
    <div class={[
      "fixed inset-0 z-50 flex items-center justify-center bg-background/90 backdrop-blur-sm animate-fade-in",
      @class
    ]}>
      <div class="bg-surface border border-border p-10 text-center shadow-medium animate-scale-in">
        <.spinner size={:lg} />
        <p class="mt-5 text-text-secondary font-display text-sm uppercase tracking-wider"><%= @message %></p>
      </div>
    </div>
    """
  end

  @doc """
  Renders an error card for fallback UI when data cannot be loaded.

  ## Examples

      <.error_card title="Failed to load sessions" message="Database connection error" />
  """
  attr(:title, :string, default: "Error", doc: "error title")
  attr(:message, :string, default: "Something went wrong", doc: "error message")
  attr(:retry, :boolean, default: false, doc: "show retry button")
  attr(:class, :string, default: nil, doc: "additional CSS classes")

  def error_card(assigns) do
    ~H"""
    <div class={[
      "bg-surface border border-status-dead/40 p-8 text-center relative",
      @class
    ]}>
      <%!-- Error accent line --%>
      <div class="absolute left-0 top-0 bottom-0 w-1 bg-status-dead"></div>

      <div class="pl-4">
        <div class="flex items-center justify-center gap-2 mb-3">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-5 h-5 text-status-dead">
            <path fill-rule="evenodd" d="M8 15A7 7 0 1 0 8 1a7 7 0 0 0 0 14ZM8 4a.75.75 0 0 1 .75.75v3a.75.75 0 0 1-1.5 0v-3A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clip-rule="evenodd" />
          </svg>
          <p class="font-display text-sm font-semibold text-status-dead uppercase tracking-wider">
            <%= @title %>
          </p>
        </div>
        <p class="text-text-secondary text-sm font-body mb-5">
          <%= @message %>
        </p>
        <.button :if={@retry} phx-click="retry" variant={:secondary}>
          Retry
        </.button>
      </div>
    </div>
    """
  end

  @doc """
  Renders breadcrumb navigation with optional links.

  ## Examples

      <.breadcrumb>
        <:item navigate="/sessions">Sessions</:item>
        <:item>Session #42</:item>
      </.breadcrumb>
  """
  attr(:class, :string, default: nil, doc: "additional CSS classes")

  slot(:item, required: true, doc: "breadcrumb item, optionally with navigate attribute") do
    attr(:navigate, :string, doc: "path to navigate to when clicked")
  end

  @spec breadcrumb(map()) :: Phoenix.LiveView.Rendered.t()

  def breadcrumb(assigns) do
    ~H"""
    <nav :if={@item != []} class={["flex items-center gap-2 font-display text-xs uppercase tracking-wider", @class]} aria-label="Breadcrumb">
      <%= for {item, index} <- Enum.with_index(@item) do %>
        <%= if index > 0 do %>
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-3 h-3 text-text-dim">
            <path fill-rule="evenodd" d="M6.22 4.22a.75.75 0 0 1 1.06 0l3.25 3.25a.75.75 0 0 1 0 1.06l-3.25 3.25a.75.75 0 0 1-1.06-1.06L8.94 8 6.22 5.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
          </svg>
        <% end %>

        <%= if index == length(@item) - 1 do %>
          <span class="text-text-primary font-semibold">
            <%= render_slot(item) %>
          </span>
        <% else %>
          <.link navigate={item[:navigate]} class="text-text-muted hover:text-accent transition-colors">
            <%= render_slot(item) %>
          </.link>
        <% end %>
      <% end %>
    </nav>
    """
  end

  @doc """
  Renders an enhanced metric card with context, trends, and optional sparkline.

  ## Examples

      <.metric_card label="Support" value="72.5%" subtitle="+3.2% this cycle" trend={:up} color={:success} />
      <.metric_card label="Cycle" value="42" subtitle="from 38" trend={:up} color={:info} sparkline_data={[10, 15, 12, 18, 20, 25, 22, 28, 30, 42]} />
  """
  attr(:label, :string, required: true, doc: "metric label displayed above the value")
  attr(:value, :any, required: true, doc: "primary metric value displayed prominently")
  attr(:subtitle, :string, default: nil, doc: "context information shown below value")

  attr(:trend, :atom,
    default: nil,
    doc: "trend indicator with arrow (:up, :down, :flat, or nil)"
  )

  attr(:color, :atom,
    default: nil,
    doc: "subtle background color tint (:success, :danger, :warning, :info, or nil)"
  )

  attr(:sparkline_data, :list,
    default: nil,
    doc: "list of numbers for sparkline chart (optional)"
  )

  attr(:class, :string, default: nil, doc: "additional CSS classes")

  @spec metric_card(map()) :: Phoenix.LiveView.Rendered.t()

  def metric_card(assigns) do
    ~H"""
    <div class={[
      "border border-border p-5 space-y-3 relative",
      metric_card_color(@color),
      @class
    ]}>
      <%!-- Subtle gradient overlay --%>
      <div class="absolute inset-0 bg-gradient-to-br from-white/[0.02] to-transparent pointer-events-none"></div>

      <div class="flex items-center justify-between relative">
        <span class="font-display text-[0.6875rem] font-semibold uppercase tracking-wider text-text-muted">
          <%= @label %>
        </span>
        <%= if @trend do %>
          <div class={["h-4 w-4", trend_color(@trend)]}>
            <%= trend_icon(@trend) %>
          </div>
        <% end %>
      </div>

      <p class="text-3xl font-mono-data font-bold text-text-primary relative">
        <%= @value %>
      </p>

      <p :if={@subtitle} class="text-sm text-text-secondary font-body relative">
        <%= @subtitle %>
      </p>

      <div :if={@sparkline_data && @sparkline_data != []} class="h-8 relative">
        <.sparkline
          data={@sparkline_data}
          width={120}
          height={32}
          color={sparkline_color(@color)}
        />
      </div>
    </div>
    """
  end

  defp metric_card_color(nil), do: "bg-surface"
  defp metric_card_color(:success), do: "bg-metric-success"
  defp metric_card_color(:danger), do: "bg-metric-danger"
  defp metric_card_color(:warning), do: "bg-metric-warning"
  defp metric_card_color(:info), do: "bg-metric-info"

  defp sparkline_color(nil), do: "#606060"
  defp sparkline_color(:success), do: "#22c55e"
  defp sparkline_color(:danger), do: "#ef4444"
  defp sparkline_color(:warning), do: "#eab308"
  defp sparkline_color(:info), do: "#3b82f6"
  defp sparkline_color(:accent), do: "#06b6d4"

  defp trend_color(:up), do: "text-status-active"
  defp trend_color(:down), do: "text-status-dead"
  defp trend_color(:flat), do: "text-text-muted"

  defp trend_icon(:up) do
    assigns = %{}

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" stroke-linejoin="miter">
      <polyline points="18 15 12 9 6 15"></polyline>
    </svg>
    """
  end

  defp trend_icon(:down) do
    assigns = %{}

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" stroke-linejoin="miter">
      <polyline points="6 9 12 15 18 9"></polyline>
    </svg>
    """
  end

  defp trend_icon(:flat) do
    assigns = %{}

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" stroke-linejoin="miter">
      <line x1="5" y1="12" x2="19" y2="12"></line>
    </svg>
    """
  end

  @doc """
  Renders a live indicator with pulsing dot animation.

  Used to indicate running sessions or active processes.

  ## Examples

      <.live_indicator />
      <.live_indicator class="ml-2" />
  """
  attr(:class, :string, default: nil, doc: "additional CSS classes")

  @spec live_indicator(map()) :: Phoenix.LiveView.Rendered.t()

  def live_indicator(assigns) do
    ~H"""
    <span class={["relative inline-flex h-2 w-2", @class]}>
      <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-status-active"></span>
      <span class="relative inline-flex rounded-full h-2 w-2 bg-status-active"></span>
    </span>
    """
  end

  @doc """
  Renders a mini sparkline chart as an SVG path.

  The sparkline displays trend data as a simple line without axes or labels.
  Data points are evenly distributed horizontally and scaled vertically to fit.

  ## Examples

      <.sparkline data={[10, 15, 12, 18, 20]} width={100} height={30} color="#00ff00" />
      <.sparkline data={[5, 8, 6, 9, 7, 10, 8]} color="#ff0000" />
      <.sparkline data={[42]} width={80} height={20} color="#0088ff" />
  """
  attr(:data, :list, default: [], doc: "list of numbers to plot")
  attr(:width, :integer, default: 100, doc: "SVG width in pixels")
  attr(:height, :integer, default: 30, doc: "SVG height in pixels")
  attr(:color, :string, default: "#00ff00", doc: "stroke color for the line")
  attr(:class, :string, default: nil, doc: "additional CSS classes")

  @spec sparkline(map()) :: Phoenix.LiveView.Rendered.t()

  def sparkline(assigns) do
    ~H"""
    <svg
      width={@width}
      height={@height}
      viewBox={"0 0 #{@width} #{@height}"}
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d={build_sparkline_path(@data, @width, @height)}
        fill="none"
        stroke={@color}
        stroke-width="2"
        stroke-linecap="square"
        stroke-linejoin="miter"
      />
    </svg>
    """
  end

  defp build_sparkline_path([], _width, _height), do: ""

  defp build_sparkline_path([_single], width, height) do
    "M 0 #{div(height, 2)} L #{width} #{div(height, 2)}"
  end

  defp build_sparkline_path(data, width, height) do
    {min_val, max_val} = Enum.min_max(data)
    range = max(max_val - min_val, 1)
    count = length(data)

    data
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      x = if count > 1, do: round(index / (count - 1) * width), else: 0
      y = height - round((value - min_val) / range * height)
      "#{if index == 0, do: "M", else: "L"} #{x} #{y}"
    end)
    |> Enum.join(" ")
  end

  @doc """
  Renders a session card displaying session information with click-to-navigate.

  The card shows the session's claim, metrics, status, and relative timestamp.
  On hover, it reveals the full claim and a "View details" indicator.

  ## Examples

      <.session_card
        id={1}
        claim="The claim text"
        cycle_count={42}
        support_strength={0.75}
        status={:running}
        inserted_at={~U[2024-01-01 12:00:00Z]}
        navigate="/sessions/1"
      />
  """
  attr(:id, :integer, required: true, doc: "session ID")
  attr(:claim, :string, required: true, doc: "current claim text")
  attr(:cycle_count, :integer, required: true, doc: "number of cycles")
  attr(:support_strength, :float, required: true, doc: "support strength value (0.0-1.0)")

  attr(:status, :atom,
    required: true,
    values: [:running, :paused, :stopped, :graduated, :dead, :completed],
    doc: "session status"
  )

  attr(:inserted_at, :any, required: true, doc: "when the session was created")
  attr(:navigate, :string, required: true, doc: "path to navigate to on click")
  attr(:class, :string, default: nil, doc: "additional CSS classes")

  @spec session_card(map()) :: Phoenix.LiveView.Rendered.t()

  def session_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "session-card group relative block border border-border bg-surface hover:bg-surface-elevated transition-all duration-150 cursor-pointer",
        "border-l-3",
        status_border_class(@status),
        @class
      ]}
    >
      <%!-- Hover glow effect --%>
      <div class="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-200 pointer-events-none">
        <div class="absolute inset-0 bg-gradient-to-r from-accent/5 to-transparent"></div>
      </div>

      <div class="p-5 relative">
        <div class="flex items-start justify-between gap-4 mb-3">
          <div class="flex items-center gap-2.5 flex-1">
            <%= if @status == :running do %>
              <.live_indicator class="flex-shrink-0" />
            <% end %>
            <span class="font-display text-[0.6875rem] font-semibold uppercase tracking-wider text-text-muted">
              Session <%= @id %>
            </span>
          </div>

          <div class="flex items-center gap-2 flex-shrink-0">
            <.status_badge status={@status} />
            <span class="text-text-muted opacity-0 group-hover:opacity-100 transition-all duration-200 translate-x-0 group-hover:translate-x-0.5">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-4 h-4">
                <path fill-rule="evenodd" d="M6.22 4.22a.75.75 0 0 1 1.06 0l3.25 3.25a.75.75 0 0 1 0 1.06l-3.25 3.25a.75.75 0 0 1-1.06-1.06L8.94 8 6.22 5.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
              </svg>
            </span>
          </div>
        </div>

        <div class="mb-4">
          <p class="font-body text-sm text-text-secondary leading-relaxed line-clamp-2 group-hover:text-text-primary transition-colors">
            <%= @claim || "No claim" %>
          </p>
        </div>

        <%!-- Metrics bar --%>
        <div class="flex items-center justify-between gap-4 pt-3 border-t border-border-subtle">
          <div class="flex items-center gap-5">
            <div class="flex items-center gap-1.5">
              <span class="font-display text-[0.625rem] font-medium uppercase tracking-wider text-text-dim">Cycles</span>
              <span class="font-mono-data text-sm text-text-primary"><%= @cycle_count %></span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="font-display text-[0.625rem] font-medium uppercase tracking-wider text-text-dim">Support</span>
              <span class={["font-mono-data text-sm", support_color(@support_strength)]}>
                <%= format_support(@support_strength) %>
              </span>
            </div>
          </div>
          <div class="font-body text-xs text-text-muted">
            <%= relative_time(@inserted_at) %>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp status_border_class(:running), do: "border-l-status-active"
  defp status_border_class(:active), do: "border-l-status-active"
  defp status_border_class(:paused), do: "border-l-status-paused"
  defp status_border_class(:graduated), do: "border-l-status-graduated"
  defp status_border_class(:completed), do: "border-l-status-graduated"
  defp status_border_class(:stopped), do: "border-l-status-dead"
  defp status_border_class(:dead), do: "border-l-status-dead"

  defp support_color(support) when support >= 0.7, do: "text-status-active"
  defp support_color(support) when support >= 0.4, do: "text-status-paused"
  defp support_color(_support), do: "text-status-dead"

  defp format_support(support), do: "#{Float.round(support * 100, 1)}%"

  defp relative_time(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> relative_time(dt)
      _ -> "Unknown"
    end
  end

  defp relative_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 172_800 -> "yesterday"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> "long ago"
    end
  end

  defp relative_time(_), do: "Unknown"

  @doc """
  Renders a collapsible section with header that toggles visibility.

  The section state persists in sessionStorage across page refreshes within
  a tab session. Triangle icon points right when collapsed, down when expanded.

  ## Examples

      <.collapsible_section id="recent-sessions" title="Recent Sessions" count={3}>
        <p>Session content here</p>
      </.collapsible_section>

      <.collapsible_section id="metrics" title="Metrics" expanded={true}>
        <:title>Custom Title</:title>
        <p>Metrics content here</p>
      </.collapsible_section>
  """
  attr(:id, :string, required: true, doc: "unique identifier for the section")
  attr(:count, :integer, default: nil, doc: "optional badge count shown in header")
  attr(:expanded, :boolean, default: false, doc: "default expanded state (true = expanded)")

  attr(:status, :atom,
    default: nil,
    doc: "status color for count badge (:active, :paused, :dead, :graduated, or nil)"
  )

  attr(:class, :string, default: nil, doc: "additional CSS classes for the container")
  attr(:header_class, :string, default: nil, doc: "additional CSS classes for the header")

  slot(:title, doc: "custom title slot (overrides default title display)")
  slot(:inner_block, required: true, doc: "collapsible content")

  @spec collapsible_section(map()) :: Phoenix.LiveView.Rendered.t()

  def collapsible_section(assigns) do
    ~H"""
    <div id={@id} phx-hook="CollapsibleSectionHook" data-expanded={@expanded} class={["border-2 border-border", @class]}>
      <button
        type="button"
        class={[
          "w-full flex items-center justify-between p-4 text-left",
          "bg-surface-elevated hover:bg-border transition-colors",
          @header_class
        ]}
        aria-expanded="true"
        aria-controls={"#{@id}-content"}
      >
        <span class="flex items-center gap-3 flex-1 min-w-0">
          <span id={"#{@id}-icon"} class="flex-shrink-0 text-text-muted transition-transform">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square" stroke-linejoin="miter" class="w-4 h-4">
              <polyline points="9 6 15 12 9 18"></polyline>
            </svg>
          </span>

          <%= if @title != [] do %>
            <span class="text-sm font-bold uppercase tracking-wider text-text-primary truncate">
              <%= render_slot(@title) %>
            </span>
          <% else %>
            <span class="text-sm font-bold uppercase tracking-wider text-text-primary">
              Section
            </span>
          <% end %>

          <span
            :if={@count && @count > 0}
            class={[
              "inline-flex items-center px-2 py-0.5 text-xs font-bold border",
              count_badge_color(@status)
            ]}
          >
            <%= @count %>
          </span>
        </span>
      </button>

      <div
        id={"#{@id}-content"}
        class="px-4 pb-4 pl-8"
      >
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  defp count_badge_color(:active),
    do: "bg-status-active/10 text-status-active border-status-active"

  defp count_badge_color(:running),
    do: "bg-status-active/10 text-status-active border-status-active"

  defp count_badge_color(:paused),
    do: "bg-status-paused/10 text-status-paused border-status-paused"

  defp count_badge_color(:dead), do: "bg-status-dead/10 text-status-dead border-status-dead"
  defp count_badge_color(:stopped), do: "bg-status-dead/10 text-status-dead border-status-dead"

  defp count_badge_color(:graduated),
    do: "bg-status-graduated/10 text-status-graduated border-status-graduated"

  defp count_badge_color(_), do: "bg-surface-elevated text-text-muted border-border"

  @doc """
  Renders a modal dialog with animated backdrop and content.

  The modal uses fade-in animation for the backdrop (100ms) and
  slide-down + fade-in for the content (100ms), both with ease-out timing.
  Users with prefers-reduced-motion get instant transitions.

  ## Examples

      <.modal id="confirm-modal" show={@show_modal} on_close={JS.push("cancel")}>
        <:title>Confirm Action</:title>
        <p>Are you sure you want to proceed?</p>
        <:actions>
          <.button phx-click="cancel">Cancel</.button>
          <.button phx-click="confirm">Confirm</.button>
        </:actions>
      </.modal>
  """
  attr(:id, :string, required: true, doc: "unique identifier for the modal")
  attr(:show, :boolean, required: true, doc: "whether the modal is visible")
  attr(:on_close, :any, required: true, doc: "JS command to close the modal")

  attr(:class, :string, default: nil, doc: "additional CSS classes for modal content")
  attr(:size, :atom, default: :md, values: [:sm, :md, :lg], doc: "modal max width")

  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the modal container")

  slot(:title, doc: "modal title")
  slot(:inner_block, required: true, doc: "modal content")
  slot(:actions, doc: "action buttons (typically Cancel and Confirm)")

  @spec modal(map()) :: Phoenix.LiveView.Rendered.t()

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show("##{@id}")}
      phx-remove={hide("##{@id}")}
      class={["fixed inset-0 z-50 flex items-center justify-center", if(!@show, do: "hidden")]}
      {@rest}
    >
      <%!-- Backdrop --%>
      <div
        class={["absolute inset-0 bg-background/80 modal-backdrop", if(!@show, do: "closing")]}
        phx-click={@on_close}
        aria-hidden="true"
      >
      </div>

      <%!-- Modal Content --%>
      <div
        class={[
          "relative bg-surface border-2 border-border p-6 w-full mx-4 modal-content",
          modal_size(@size),
          if(!@show, do: "closing"),
          @class
        ]}
        phx-click-away={@on_close}
        phx-window-keydown={@on_close}
        phx-key="escape"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
      >
        <div class="flex items-start justify-between mb-4">
          <h2 id={"#{@id}-title"} class="text-lg font-bold uppercase tracking-wider text-text-primary">
            <%= if @title != [] do %>
              <%= render_slot(@title) %>
            <% else %>
              Modal
            <% end %>
          </h2>
        </div>

        <div class="text-text-secondary mb-6">
          <%= render_slot(@inner_block) %>
        </div>

        <div :if={@actions != []} class="flex justify-end gap-3">
          <%= render_slot(@actions) %>
        </div>
      </div>
    </div>
    """
  end

  defp modal_size(:sm), do: "max-w-sm"
  defp modal_size(:md), do: "max-w-md"
  defp modal_size(:lg), do: "max-w-lg"
end
