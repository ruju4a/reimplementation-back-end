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
  # Resolves the participant's team, fetches all ReviewResponseMaps for that team,
  # then delegates to the shared base-class helper to filter by round and submission
  # status. Results are sorted alphabetically by reviewer full name.
  def get_assessments_for_round(participant, round)
    team = AssignmentTeam.team(participant)
    return nil unless team

    maps = ResponseMap.where(reviewee_id: team.id, type: 'ReviewResponseMap')
    responses = filter_submitted_responses_for_round(maps, round)
    responses.sort! { |a, b| a.map.reviewer.fullname <=> b.map.reviewer.fullname }
    responses
  end
end
