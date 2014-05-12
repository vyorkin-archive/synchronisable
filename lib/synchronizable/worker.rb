require 'synchronizable/error_handler'
require 'synchronizable/context'
require 'synchronizable/source'
require 'synchronizable/models/import'

require 'pry-byebug'

module Synchronizable
  # Responsible for model synchronization.
  #
  # @api private
  class Worker
    class << self
      # Creates a new instance of worker and initiates model synchronization.
      #
      # @overload run(model, data, options)
      #   @param model [Class] model class to be synchronized
      #   @param options [Hash] synchronization options
      #   @option options [Hash] :include assocations to be synchronized.
      #     Use this option to override `has_one` & `has_many` assocations
      #     defined in model synchronizer.
      # @overload run(model, data)
      # @overload run(model)
      #
      # @return [Synchronizable::Context] synchronization context
      def run(model, *args)
        options = args.extract_options!
        data = args.first

        new(model, options).run(data)
      end
    end

    # Initiates model synchronization.
    #
    # @param data [Array<Hash>] array of hashes with remote attriutes.
    #   If not specified worker will try to get the data
    #   using `fetch` lambda/proc defined in corresponding synchronizer
    #
    # @return [Synchronizable::Context] synchronization context
    def run(data)
      sync do |context|
        error_handler = ErrorHandler.new(@logger, context)
        context.before = @model.imports_count

        data = @synchronizer.fetch.() if data.blank?
        data.each do |attrs|
          # TODO: Handle case when only array of ids is given
          # What to do with associations?

          source = Source.new(model, parent, attrs)
          error_handler.handle(source) do
            @synchronizer.with_sync_callbacks(source) do
              sync_record(source)
              sync_associations(source)
            end
          end
        end

        context.after = @model.imports_count
        context.deleted = 0
      end
    end

    private

    def initialize(model, options)
      @model, @synchronizer = model, model.synchronizer
      @logger = @synchronizer.logger
      @options = options
    end

    def sync
      @logger.progname = "#{@model} synchronization"
      @logger.info { 'starting' }

      context = Context.new(@model, @parent.try(:model))
      yield context

      @logger.info { 'done' }
      @logger.info { context.summary_message }
      @logger.progname = nil

      context
    end

    # TODO: Think about how to move it from here to Source or some other place

    # Method called by {#run} for each remote model attribute hash
    #
    # @param source [Synchronizable::Source] synchronization source
    #
    # @return [Boolean] `true` if synchronization was completed
    #   without errors, `false` otherwise
    def sync_record(source)
      @synchronizer.with_record_sync_callbacks(source) do
        source.build(@model)

        @logger.info { source.dump_message } if verbose_logging?

        if source.updatable?
          update_record(source)
        else
          create_record_pair(source)
        end
      end
    end

    def update_record(source)
      if verbose_logging?
        @logger.info { "updating #{@model}: #{source.local_record.id}" }
      end

      # TODO: Напрашивается, да?
      source.local_record.update_attributes!(source.local_attrs)
    end

    def create_record_pair(source)
      local_record = @model.create!(source.local_attrs)
      import_record = Import.create!(
        :synchronizable_id    => local_record.id,
        :synchronizable_type  => @model.to_s,
        :remote_id            => source.remote_id,
        :attrs                => source.local_attrs
      )

      source.import_record = import_record

      if verbose_logging?
        @logger.info { "#{@model}: #{local_record.id} was created" }
        @logger.info { "#{import_record.class}: #{import_record.id} was created" }
      end
    end

    # Synchronizes associations.
    #
    # @param source [Synchronizable::Source] synchronization source
    #
    # @see Synchronizable::DSL::Associations
    # @see Synchronizable::DSL::Associations::Association
    def sync_associations(source)
      if verbose_logging? && source.associations.present?
        @logger.info { "starting associations sync" }
      end

      source.associations.each do |association, ids|
        ids.each { |id| sync_association(source, id, association) }
      end
    end

    def sync_association(source, id, association)
      binding.pry
      if verbose_logging?
        @logger.info { "synchronizing association with id: #{id}" }
      end

      @synchronizer.with_association_sync_callbacks(source, id, association) do
        attrs = association.model.synchronizer.find.(id)
        Worker.run(association.model, [attrs], { :parent => source })
      end
    end

    def verbose_logging?
      Synchronizable.logging[:verbose]
    end
  end
end
