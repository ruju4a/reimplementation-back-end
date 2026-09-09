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
  def get_assessments_for_round(participant, round)
    team = AssignmentTeam.team(participant)
    return nil unless team

    responses = []
    # Find all ReviewResponseMaps where the team being reviewed is the participant's team.
    maps = ResponseMap.where(reviewee_id: team.id, type: 'ReviewResponseMap')
    maps.each do |map|
      # Skip maps that have no responses yet.
      next if map.responses.empty?

      # Collect only responses that match the requested round and are submitted.
      map.responses.each do |response|
        responses << response if response.round == round && response.is_submitted
      end
    end
    # Return responses sorted alphabetically by the reviewer's full name.
    responses.sort! { |a, b| a.map.reviewer.fullname <=> b.map.reviewer.fullname }
    responses
  end
end
