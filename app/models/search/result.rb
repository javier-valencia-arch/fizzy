class Search::Result < ApplicationRecord
  belongs_to :creator, class_name: "User"
  belongs_to :card, foreign_key: :card_id, optional: true
  belongs_to :comment, foreign_key: :comment_id, optional: true

  def source
    comment_id.present? ? comment : card
  end

  def readonly?
    true
  end
end
