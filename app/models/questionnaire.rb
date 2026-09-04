# frozen_string_literal: true

class Questionnaire < ApplicationRecord
  belongs_to :instructor
  has_many :items, class_name: "Item", foreign_key: "questionnaire_id", dependent: :destroy
  before_destroy :check_for_question_associations

  # Subclasses declare @print_name = '...' and inherit this reader automatically.
  class << self
    attr_reader :print_name
  end

  validate :validate_questionnaire
  validates :name, presence: true
  validates :max_question_score, :min_question_score, numericality: true

  # Scored rubric subclasses must override these.
  def symbol
    raise NotImplementedError, "#{self.class}#symbol not implemented"
  end

  def get_assessments_for(_participant)
    raise NotImplementedError, "#{self.class}#get_assessments_for not implemented"
  end

  def validate_questionnaire
    errors.add(:max_question_score, 'The maximum item score must be a positive integer.') if max_question_score < 1
    errors.add(:min_question_score, 'The minimum item score must be a positive integer.') if min_question_score < 0
    errors.add(:min_question_score, 'The minimum item score must be less than the maximum.') if min_question_score >= max_question_score
    results = Questionnaire.where('id <> ? and name = ? and instructor_id = ?', id, name, instructor_id)
    errors.add(:name, 'Questionnaire names must be unique.') if results.present?
  end

  # Duplicates a questionnaire along with its items and advice.
  def self.copy_questionnaire_details(params)
    orig_questionnaire = Questionnaire.find(params[:id])
    items = Item.where(questionnaire_id: params[:id])
    questionnaire = orig_questionnaire.dup
    questionnaire.instructor_id = params[:instructor_id]
    questionnaire.name = 'Copy of ' + orig_questionnaire.name
    questionnaire.created_at = Time.zone.now
    questionnaire.save!
    items.each do |question|
      new_question = question.dup
      new_question.questionnaire_id = questionnaire.id
      new_question.size = '50,3' if (new_question.is_a?(Criterion) || new_question.is_a?(TextResponse)) && new_question.size.nil?
      new_question.save!
      advice = QuestionAdvice.where(question_id: question.id)
      next if advice.empty?

      advice.each do |advice|
        new_advice = advice.dup
        new_advice.question_id = new_question.id
        new_advice.save!
      end
    end
    questionnaire
  end

  def check_for_question_associations
    if items.any?
      raise ActiveRecord::DeleteRestrictionError.new("Cannot delete record because dependent items exist")
    end
  end

  def as_json(options = {})
    super(options.merge({
      only: %i[id name private min_question_score max_question_score created_at updated_at questionnaire_type instructor_id],
      include: {
        instructor: { only: %i[name email fullname password role] }
      }
    })).tap do |hash|
      hash['instructor'] ||= { id: nil, name: nil }
    end
  end

  DEFAULT_MIN_QUESTION_SCORE = 0
  DEFAULT_MAX_QUESTION_SCORE = 5
  DEFAULT_QUESTIONNAIRE_URL = 'http://www.courses.ncsu.edu/csc517'.freeze

  QUESTIONNAIRE_TYPES = [
    'ReviewQuestionnaire',
    'AuthorFeedbackQuestionnaire',
    'BookmarkRatingQuestionnaire',
    'QuizQuestionnaire',
    'SurveyQuestionnaire',
    'CourseEvaluationQuestionnaire',
    'TeammateReviewQuestionnaire',
    'GlobalSurveyQuestionnaire'
  ].freeze

  # Computes the weighted score for this questionnaire within an assignment,
  # accounting for multi-round rubrics via a round suffix on the symbol.
  def get_weighted_score(assignment, scores)
    round = AssignmentQuestionnaire.find_by(assignment_id: assignment.id, questionnaire_id: id).used_in_round
    questionnaire_symbol = round.nil? ? symbol : (symbol.to_s + round.to_s).to_sym
    compute_weighted_score(questionnaire_symbol, assignment, scores)
  end

  def compute_weighted_score(symbol, assignment, scores)
    aq = AssignmentQuestionnaire.find_by(assignment_id: assignment.id)
    if scores[symbol][:scores][:avg].nil?
      0
    else
      scores[symbol][:scores][:avg] * aq.questionnaire_weight / 100.0
    end
  end

  def true_false_items?
    items.each { |question| return true if question.type == 'Checkbox' }
    false
  end

  # Sum of weights for scored items, excluding SectionHeaders.
  def total_item_weight
    items.reject { |i| i.question_type == 'SectionHeader' }.sum(&:weight)
  end

  def max_possible_score
    results = Questionnaire.joins('INNER JOIN items ON items.questionnaire_id = questionnaires.id')
                           .select('SUM(items.weight) * questionnaires.max_question_score as max_score')
                           .where('questionnaires.id = ?', id)
    results[0].max_score
  end
end
