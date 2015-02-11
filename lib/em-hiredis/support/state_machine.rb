require 'set'

module EventMachine::Hiredis
  class StateMachine
    include EventMachine::Hiredis::EventEmitter

    attr_reader :state

    def initialize
      @transitions = {}
      @state = :initial
      @all_states = Set.new([:initial])
    end

    def transition(from, to)
      @all_states.add(from)
      @all_states.add(to)
      @transitions[from] ||= []
      @transitions[from].push(to)
     end

    def update_state(to)
      raise "Invalid state #{to}" unless @all_states.include?(to)

      allowed = @transitions[@state] && @transitions[@state].include?(to)
      raise "No such transition #{@state} #{to}" unless allowed

      old_state = @state
      @state = to
      emit(to, old_state)
    end
  end
end
