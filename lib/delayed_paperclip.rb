require 'delayed_paperclip/process_job'
require 'delayed_paperclip/attachment'
require 'delayed_paperclip/url_generator'
require 'delayed_paperclip/railtie' if defined?(Rails)

module DelayedPaperclip
  class << self
    def options
      @options ||= {
        :background_job_class => DelayedPaperclip::ProcessJob,
        :url_with_processing  => true,
        :processing_image_url => nil,
        :queue => "paperclip"
      }
    end

    def processor
      options[:background_job_class]
    end

    def enqueue(instance_klass, instance_id, attachment_name, parent, parent_id)
      processor.enqueue_delayed_paperclip(instance_klass, instance_id.to_s, attachment_name, parent, parent_id)
    end

    def process_job(instance_klass, instance_id, attachment_name, parent, parent_id)
      if parent.present?
        #search for embedded instance
        parent_object        = parent.constantize.find(parent_id)
        association_result   = parent_object.reflect_on_all_associations.select {|rel| rel[:class_name] == instance_klass.to_s }.first
        name                 = association_result[:name]
        instance = parent_object.send(name).find(instance_id)
        return if instance.blank?
      else
        #just search for an
        instance = instance_klass.constantize.unscoped.where(id: instance_id.to_s).first
        return if instance.blank?
      end

      instance.
        send(attachment_name).
        process_delayed!
    end

  end

  module Glue
    def self.included(base)
      base.extend(ClassMethods)
      base.send :include, InstanceMethods
    end
  end

  module ClassMethods

    def process_in_background(name, options = {})
      # initialize as hash
      paperclip_definitions[name][:delayed] = {}

      # Set Defaults
      only_process_default = paperclip_definitions[name][:only_process]
      only_process_default ||= []
      {
        :priority => 0,
        :only_process => only_process_default,
        :url_with_processing => DelayedPaperclip.options[:url_with_processing],
        :processing_image_url => DelayedPaperclip.options[:processing_image_url],
        :queue => DelayedPaperclip.options[:queue]
      }.each do |option, default|
        paperclip_definitions[name][:delayed][option] = options.key?(option) ? options[option] : default
      end

      # Sets callback
      if respond_to?(:after_commit)
        after_commit  :enqueue_delayed_processing
      else
        after_save    :enqueue_delayed_processing
      end
    end

    def paperclip_definitions
      if respond_to? :attachment_definitions
        attachment_definitions
      else
        Paperclip::Tasks::Attachments.definitions_for(self)
      end
    end
  end

  module InstanceMethods

    # First mark processing
    # then enqueue
    def enqueue_delayed_processing
      mark_enqueue_delayed_processing
      (@_enqued_for_processing || []).each do |name|
        enqueue_post_processing_for(name)
      end
      @_enqued_for_processing_with_processing = []
      @_enqued_for_processing = []
    end

    # setting each inididual NAME_processing to true, skipping the ActiveModel dirty setter
    # Then immediately push the state to the database
    def mark_enqueue_delayed_processing
      unless @_enqued_for_processing_with_processing.blank? # catches nil and empty arrays
        #updates = @_enqued_for_processing_with_processing.collect{|n| "#{n}_processing = :true" }.join(", ")
        #updates = ActiveRecord::Base.send(:sanitize_sql_array, [updates, {:true => true}])
        #self.class.unscoped.where(:id => self.id).update_all(updates)
        self.set(image_processing: true) #no callback fired
      end
    end

    def enqueue_post_processing_for name#, embeded_in
      parent    = self._parent.present? ? self._parent.class : nil
      parent_id = self._parent.present? ? self._parent.id :  nil
      DelayedPaperclip.enqueue(self.class.name, read_attribute(:id).to_s,
                               name.to_sym,
                               parent,
                               parent_id)
      
    end
    def prepare_enqueueing_for name
      if self.attributes.has_key? "#{name}_processing"
        self.set(image_processing: true) #no callback fired
        @_enqued_for_processing_with_processing ||= []
        @_enqued_for_processing_with_processing << name
      end
      @_enqued_for_processing ||= []
      @_enqued_for_processing << name
    end
  end
end
