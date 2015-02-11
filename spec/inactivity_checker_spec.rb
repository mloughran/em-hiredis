require 'spec_helper'

describe EM::Hiredis::InactivityChecker do
  def setup(inactivity_time, reponse_time)
    em = EM::Hiredis::TimeMockEventMachine.new
    subject = EM::Hiredis::InactivityChecker.new(inactivity_time, reponse_time, em)
    yield(subject, em)
  end

  it 'should emit after activity timeout reached' do
    setup(3, 1) do |checker, em|
      emitted = false
      checker.on(:activity_timeout) {
        emitted = true
        em.current_time.should == 4
        checker.stop
      }

      checker.start
      em.evaluate_ticks

      emitted.should == true
    end
  end

  it 'should not ping before activity timeout exceeded' do
    setup(4, 1) do |checker, em|
      checker.on(:activity_timeout) {
        fail
      }

      em.add_timer(4) {
        checker.stop
      }

      checker.start
      em.evaluate_ticks

      em.current_time.should == 4
    end  end

  it 'should not ping if there is activity' do
    setup(3, 1) do |checker, em|
      checker.on(:activity_timeout) {
        fail
      }

      em.add_timer(2) {
        checker.activity
      }

      em.add_timer(4) {
        checker.activity
      }

      em.add_timer(6) {
        checker.stop
      }

      checker.start
      em.evaluate_ticks

      em.current_time.should == 6
    end
  end

  it 'should emit after response timeout exceeded' do
    setup(3, 1) do |checker, em|
      emitted = []
      checker.on(:activity_timeout) {
        emitted << :activity_timeout

        em.current_time.should == 4
      }
      checker.on(:response_timeout) {
        emitted << :response_timeout

        em.current_time.should == 5
        checker.stop
      }

      checker.start
      em.evaluate_ticks

      emitted.should == [:activity_timeout, :response_timeout]
    end
  end

  it 'should emit after period of activity followed by inactivity' do
    setup(3, 1) do |checker, em|
      em.add_timer(2) {
        checker.activity
      }

      em.add_timer(4) {
        checker.activity
      }

      em.add_timer(6) {
        checker.activity
      }

      emitted = []
      checker.on(:activity_timeout) {
        emitted << :activity_timeout

        em.current_time.should == 10
      }
      checker.on(:response_timeout) {
        emitted << :response_timeout

        em.current_time.should == 11
        checker.stop
      }

      checker.start
      em.evaluate_ticks

      emitted.should == [:activity_timeout, :response_timeout]
    end
  end
end
