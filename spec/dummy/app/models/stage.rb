class Stage < ActiveRecord::Base
  belongs_to :tournament
  has_many :matches

  synchronizable
end
