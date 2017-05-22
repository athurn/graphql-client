# frozen_string_literal: true
require "graphql/client/error"

module GraphQL
  class Client
    # Raised when method is called from outside the expected file scope.
    class NonCollocatedCallerError < Error; end

    # Enforcements collocated object access best practices.
    module CollocatedEnforcement
      # Public: Ignore collocated caller enforcement for the scope of the block.
      def allow_noncollocated_callers
        Thread.current[:query_result_caller_location_ignore] = true
        yield
      ensure
        Thread.current[:query_result_caller_location_ignore] = nil
      end

      # Collcation will not be enforced if a stack trace includes any of these gems.
      WHITELISTED_DEBUGGING_LOCATIONS = /gems\/pry|gems\/byebug/

      # Internal: Check if called from debugger library.
      #
      # locations - Array of caller location Thread::Backtrace::Locations
      #
      # Returns true if enforcement should be ignored.
      def self.allowed_debugging_call?(locations)
        locations.any? do |location|
          location.path =~ WHITELISTED_DEBUGGING_LOCATIONS
        end
      end

      # Internal: Decorate method with collocated caller enforcement.
      #
      # mod - Target Module/Class
      # methods - Array of Symbol method names
      # paths - Array of String filenames to assert calling from
      #
      # Returns nothing.
      def enforce_collocated_callers(mod, methods, paths)
        paths = Set.new(Array(paths))

        mod.prepend(Module.new do
          methods.each do |method|
            define_method(method) do |*args, &block|
              return super(*args, &block) if Thread.current[:query_result_caller_location_ignore]

              if !paths.include?(caller_locations(1, 1)[0].path) && !CollocatedEnforcement.allowed_debugging_call?(caller_locations(1, 5))
                error = NonCollocatedCallerError.new("#{method} was called outside of '#{paths.to_a.join(", ")}' https://git.io/v1syX")
                error.set_backtrace(caller(1))
                raise error
              end

              begin
                Thread.current[:query_result_caller_location_ignore] = true
                super(*args, &block)
              ensure
                Thread.current[:query_result_caller_location_ignore] = nil
              end
            end
          end
        end)
      end
    end
  end
end
