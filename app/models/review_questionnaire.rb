# frozen_string_literal: true

class ReviewQuestionnaire < Questionnaire
  after_initialize :post_initialization
  @print_name = 'Review Rubric'

  def post_initialization
    self.display_type = 'Review'
  end

  def symbol
    'review'.to_sym
  end

  def get_assessments_for(participant)
    participant.reviews
  end

  # Returns submitted responses for the given participant in a specific round.
  def get_assessments_round_for(participant, round)
    team = AssignmentTeam.team(participant)
    return nil unless team

    responses = []
    maps = ResponseMap.where(reviewee_id: team.id, type: 'ReviewResponseMap')
    maps.each do |map|
      next if map.response.empty?

      map.response.each do |response|
        responses << response if response.round == round && response.is_submitted
      end
    end
    responses.sort! { |a, b| a.map.reviewer.fullname <=> b.map.reviewer.fullname }
    responses
  end
end
