# frozen_string_literal: true

require 'cucumber/formatter/io'
require 'cucumber/formatter/query/hook_by_test_step'
require 'cucumber/formatter/query/pickle_by_test'
require 'cucumber/formatter/query/pickle_step_by_test_step'
require 'cucumber/formatter/query/step_definitions_by_test_step'


module Cucumber
  module Formatter
    # The formatter used for <tt>--format message</tt>
    class Message
      include Io

      def initialize(config)
        @config = config
        @hook_by_test_step = Query::HookByTestStep.new(config)
        @pickle_by_test = Query::PickleByTest.new(config)
        @pickle_step_by_test_step = Query::PickleStepByTestStep.new(config)
        @step_definitions_by_test_step = Query::StepDefinitionsByTestStep.new(config)

        @io = ensure_io(config.out_stream)
        config.on_event :envelope, &method(:on_envelope)
        config.on_event :test_case_ready, &method(:on_test_case_ready)
        config.on_event :test_case_started, &method(:on_test_case_started)
        config.on_event :test_step_finished, &method(:on_test_step_finished)
        config.on_event :test_case_finished, &method(:on_test_case_finished)

        @test_case_id_by_step = {}
      end

      def output_envelope(envelope)
        envelope.write_ndjson_to(@io)
      end

      def on_envelope(event)
        output_envelope(event.envelope)
      end

      def on_test_case_ready(event)
        event.test_case.test_steps.each do |step|
          @test_case_id_by_step[step.id] = event.test_case.id
        end

        message = Cucumber::Messages::Envelope.new(
          test_case: Cucumber::Messages::TestCase.new(
            id: event.test_case.id,
            pickle_id: @pickle_by_test.pickle_id(event.test_case),
            test_steps: event.test_case.test_steps.map do |step|
              if step.hook?
                Cucumber::Messages::TestCase::TestStep.new(
                  id: step.id,
                  hook_id: @hook_by_test_step.hook_id(step)
                )
              else
                Cucumber::Messages::TestCase::TestStep.new(
                  id: step.id,
                  pickle_step_id: @pickle_step_by_test_step.pickle_step_id(step),
                  step_definition_ids: @step_definitions_by_test_step.step_definition_ids(step)
                )
              end
            end
          )
        )

        output_envelope(message)
      end

      def on_test_step_finished(event)
        # TestResult test_result = 1;
        # Timestamp timestamp = 2;
        # string test_step_id = 3;
        # string test_case_started_id = 4;

        test_case_id = @test_case_id_by_step[event.test_step.id]

        message = Cucumber::Messages::Envelope.new(
          test_step_finished: Cucumber::Messages::TestStepFinished.new(
            test_step_id: event.test_step.id,
            test_case_started_id: "#{test_case_id}-0",
            test_result: event.result.to_message
          )
        )

        output_envelope(message)
      end

      def on_test_case_started(event)
        message = Cucumber::Messages::Envelope.new(
          test_case_started: Cucumber::Messages::TestCaseStarted.new(
            id: "#{event.test_case.id}-0",
            test_case_id: event.test_case.id
          )
        )

        output_envelope(message)
      end

      def on_test_case_finished(event)
        message = Cucumber::Messages::Envelope.new(
          test_case_finished: Cucumber::Messages::TestCaseFinished.new(
            test_case_started_id: "#{event.test_case.id}-0"
          )
        )

        output_envelope(message)
      end


    end
  end
end
