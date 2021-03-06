class SetupAmqpTasks
  def initialize
    conn = Bunny.new(ExchangeInformation.amqp_uri)
    conn.start
    @ch = conn.create_channel
    @ch.prefetch(1)
  end

  def queue(q)
    @ch.queue(q, :durable => true)
  end

  def exchange(e_type, name)
    @ch.send(e_type.to_sym, name, {:durable => true})
  end

  def logging_queue(ec, name)
    q_name = "#{ec.hbx_id}.#{ec.environment}.q.#{name}"
    @ch.queue(q_name, :durable => true)
  end

  def run
    ec = ExchangeInformation

    queue(ec.invalid_argument_queue)
    queue(ec.processing_failure_queue)
    eeh_q = queue(Listeners::EnrollmentEventHandler.queue_name)
    en_sub_q = queue(Listeners::EnrollmentSubmittedHandler.queue_name)
    es_sub_q = queue(Listeners::ExchangeSequenceListener.queue_name)
    ur_sub_q = queue(Listeners::UriResolverListener.queue_name)
    ell_q = queue(Listeners::EventLoggingListener.queue_name)
    rll_q = queue(Listeners::RequestLoggingListener.queue_name)
    email_queue = queue(Listeners::EmailNotificationListener.queue_name)

    event_ex = exchange("topic", ec.event_exchange)
    event_pub_ex = exchange("fanout", ec.event_publish_exchange)
    direct_ex = exchange("direct", ec.request_exchange)

    event_ex.bind(event_pub_ex)

    ur_sub_q.bind(direct_ex, :routing_key => "uri.resolve")
    es_sub_q.bind(direct_ex, :routing_key => "sequence.next")

    ell_q.bind(event_ex, :routing_key => "#")

    eeh_q.bind(event_ex, :routing_key => "enrollment.individual.initial_enrollment")
    eeh_q.bind(event_ex, :routing_key => "enrollment.individual.renewal")
    en_sub_q.bind(event_ex, :routing_key => Listeners::EnrollmentSubmittedHandler.event_key)

    emp_qhps = logging_queue(ec, "recording.ee_qhp_plan_selected")
    ind_qhps = logging_queue(ec, "recording.ind_qhp_plan_selected")
    emp_qhps.bind(event_ex, :routing_key => "employer_employee.qhp_selected")
    ind_qhps.bind(event_ex, :routing_key => "individual.qhp_selected")

    email_queue.bind(event_ex, :routing_key => "info.user_notifications.email.published")
  end
end

SetupAmqpTasks.new.run
