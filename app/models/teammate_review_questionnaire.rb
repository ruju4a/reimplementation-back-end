# frozen_string_literal: true

class TeammateReviewQuestionnaire < Questionnaire
  after_initialize :post_initialization
  @print_name = 'Team Review Rubric'

  def post_initialization
    self.display_type = 'Teammate Review'
  end

  def symbol
    'teammate'.to_sym
  end

  def get_assessments_for(participant)
    participant.teammate_reviews
  end

  # Returns submitted responses for the given participant in a specific round.
  def get_assessments_round_for(participant, round)
    responses = []
    maps = TeammateReviewResponseMap.where(reviewer_id: participant.id)
    maps.each do |map|
      next if map.response.empty?

      map.response.each do |response|
        responses << response if response.round == round && response.is_submitted
      end
    end
    responses
  end

  # True if any items are Criterion type (rendered as percentage sliders in the UI).
  def has_percentage_questions?
    items.any? { |item| item.question_type == 'Criterion' }
  end
end
