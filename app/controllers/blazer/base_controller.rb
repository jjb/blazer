module Blazer
  class BaseController < ApplicationController
    # skip all filters
    filters = _process_action_callbacks.map(&:filter)
    if Rails::VERSION::MAJOR >= 5
      skip_before_action(*filters, raise: false)
      skip_after_action(*filters, raise: false)
      skip_around_action(*filters, raise: false)
    else
      skip_action_callback *filters
    end

    protect_from_forgery with: :exception

    if ENV["BLAZER_PASSWORD"]
      http_basic_authenticate_with name: ENV["BLAZER_USERNAME"], password: ENV["BLAZER_PASSWORD"]
    end

    if Blazer.before_action
      before_action Blazer.before_action.to_sym
    end

    layout "blazer/application"

    private

      def process_vars(statement, data_source)
        (@bind_vars ||= []).concat(extract_vars(statement)).uniq!
        @bind_vars.each do |var|
          params[var] ||= Blazer.data_sources[data_source].variable_defaults[var]
        end
        @success = @bind_vars.all? { |v| params[v] }

        if @success
          @bind_vars.each do |var|
            value = params[var].presence
            if value
              if ["start_time", "end_time"].include?(var)
                value = value.to_s.gsub(" ", "+") # fix for Quip bug
              end

              if var.end_with?("_at")
                begin
                  value = Blazer.time_zone.parse(value)
                rescue
                  # do nothing
                end
              end

              if value =~ /\A\d+\z/
                value = value.to_i
              elsif value =~ /\A\d+\.\d+\z/
                value = value.to_f
              end
            end
            statement.gsub!("{#{var}}", ActiveRecord::Base.connection.quote(value))
          end
        end
      end

      def parse_smart_variables(var, data_source)
        smart_var_data_source =
          ([data_source] + Array(data_source.settings["inherit_smart_settings"]).map { |ds| Blazer.data_sources[ds] }).find { |ds| ds.smart_variables[var] }

        if smart_var_data_source
          query = smart_var_data_source.smart_variables[var]

          if query.is_a? Hash
            smart_var = query.map { |k,v| [v, k] }
          elsif query.is_a? Array
            smart_var = query.map { |v| [v, v] }
          elsif query
            result = smart_var_data_source.run_statement(query)
            smart_var = result.rows.map { |v| v.reverse }
            error = result.error if result.error
          end
        end

        [smart_var, error]
      end

      def extract_vars(statement)
        # strip commented out lines
        # and regex {1} or {1,2}
        statement.gsub(/\-\-.+/, "").gsub(/\/\*.+\*\//m, "").scan(/\{\w*?\}/i).map { |v| v[1...-1] }.reject { |v| /\A\d+(\,\d+)?\z/.match(v) || v.empty? }.uniq
      end
      helper_method :extract_vars

      def variable_params
        params.except(:controller, :action, :id, :host, :query, :dashboard, :query_id, :query_ids, :table_names, :authenticity_token, :utf8, :_method, :commit, :statement, :data_source, :name, :fork_query_id, :blazer, :run_id).permit!
      end
      helper_method :variable_params

      def blazer_user
        send(Blazer.user_method) if Blazer.user_method && respond_to?(Blazer.user_method)
      end
      helper_method :blazer_user

      def render_errors(resource)
        @errors = resource.errors
        action = resource.persisted? ? :edit : :new
        render action, status: :unprocessable_entity
      end
  end
end
