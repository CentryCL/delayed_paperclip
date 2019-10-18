require "active_job"

module DelayedPaperclip
  class ProcessJob < ActiveJob::Base
    def self.enqueue_delayed_paperclip(instance_klass, instance_id, attachment_name, parent, parent_id)
      queue_name = instance_klass.constantize.paperclip_definitions[attachment_name][:delayed][:queue]
      set(:queue => queue_name).perform_later(instance_klass,
                                              instance_id.to_s,
                                              attachment_name.to_s,
                                              parent.to_s,
                                              parent_id.to_s)
    end

    def perform(instance_klass, instance_id, attachment_name, parent, parent_id)
      DelayedPaperclip.process_job(instance_klass,
                                   instance_id.to_s,
                                   attachment_name.to_sym,
                                   parent.to_s,
                                   parent_id.to_s)
    end
  end
end
