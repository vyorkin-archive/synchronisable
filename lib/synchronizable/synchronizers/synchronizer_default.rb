require 'synchronizable/synchronizer'

module Synchronizable
  # Default synchronizer to be used when
  # model specific synchronizer is not defined.
  #
  # @api private
  class SynchronizerDefault < Synchronizer
  end
end
