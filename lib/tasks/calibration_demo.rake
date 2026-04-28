# frozen_string_literal: true

namespace :demo do
  desc 'Seed calibration demo data: one submitter with submitted content per assignment, ' \
       'plus a full instructor + 6-student report dataset on the last assignment.'
  task calibration_report: :environment do
    institution = Institution.first || Institution.create!(name: 'North Carolina State University')

    ensure_user = lambda do |model_class:, name:, email:, role_name:, full_name:, password: 'password123', parent: nil|
      role = Role.find_by!(name: role_name)
      user = User.find_by(name: name) || User.find_by(email: email)
      if user
        user.update!(email: email, full_name: full_name, role: role, institution: institution, parent: parent)
        user.password = password if user.authenticate(password).nil?
        user.save! if user.changed?
        model_class.find(user.id)
      else
        model_class.create!(
          name: name, email: email, password: password,
          full_name: full_name, role: role, institution: institution, parent: parent
        )
      end
    end

    ensure_item = lambda do |questionnaire:, txt:, seq:|
      item = questionnaire.items.find_or_initialize_by(txt: txt)
      item.assign_attributes(seq: seq, weight: 1, question_type: 'Scale', break_before: true)
      item.save!
      item
    end

    upsert_response = lambda do |map:, scores:|
      response = Response.where(map_id: map.id, is_submitted: true).order(updated_at: :desc).first
      unless response
        response = Response.create!(
          response_map: map,
          round: 1,
          version_num: Response.where(map_id: map.id).maximum(:version_num).to_i + 1,
          is_submitted: true
        )
      end
      response.update!(is_submitted: true, updated_at: Time.current)
      scores.each do |item, score|
        answer = Answer.find_or_initialize_by(response_id: response.id, item_id: item.id)
        answer.update!(answer: score, comments: '')
      end
      response
    end

    add_submitted_content = lambda do |team:, assignment:|
      team.update!(submitted_hyperlinks: YAML.dump(["https://example.com/submission/#{assignment.id}"]))
      SubmissionRecord.find_or_create_by!(
        record_type: 'file',
        content: "submission/assignment_#{assignment.id}_report.pdf",
        operation: 'Submit File',
        team_id: team.id,
        assignment_id: assignment.id
      ) { |r| r.user = assignment.instructor.name }
    end

    assignments = Assignment.all.order(:id)
    full_demo_assignment = assignments.last

    puts "Seeding calibration demo data for #{assignments.count} assignment(s)..."

    assignments.each do |assignment|
      instructor = assignment.instructor

      submitter = ensure_user.call(
        model_class: User,
        name: "calibration_submitter_#{assignment.id}",
        email: "calibration_submitter_#{assignment.id}@example.com",
        role_name: 'Student',
        full_name: "Calibration Submitter #{assignment.id}",
        parent: instructor
      )

      row = assignment.add_calibration_submitter!(submitter)
      instructor_map = ReviewResponseMap.find(row[:instructor_review_map_id])
      team = instructor_map.reviewee

      add_submitted_content.call(team: team, assignment: assignment)

      puts "  Assignment #{assignment.id} (#{assignment.name}): submitter=#{submitter.name}, team=#{team.name}, map=#{instructor_map.id}"
    end

    # ── Full report demo on the last assignment ──────────────────────────────
    # Sets up a rubric, seeds an instructor response, and adds 6 student
    # calibration responses so the stacked chart in the report has real data.
    puts "\nSeeding full report demo on assignment #{full_demo_assignment.id} (#{full_demo_assignment.name})..."

    instructor = full_demo_assignment.instructor

    questionnaire =
      full_demo_assignment.assignment_questionnaires.find_by(used_in_round: 1)&.questionnaire ||
      Questionnaire.find_by(name: 'Calibration Demo Rubric', instructor_id: instructor.id)

    questionnaire ||= Questionnaire.create!(
      name: 'Calibration Demo Rubric',
      private: false,
      min_question_score: 0,
      max_question_score: 5,
      instructor: instructor
    )

    AssignmentQuestionnaire.find_or_create_by!(
      assignment: full_demo_assignment,
      questionnaire: questionnaire,
      used_in_round: 1
    )

    items = [
      ensure_item.call(questionnaire: questionnaire, txt: 'Code quality',  seq: 1),
      ensure_item.call(questionnaire: questionnaire, txt: 'Documentation', seq: 2),
      ensure_item.call(questionnaire: questionnaire, txt: 'Testing',       seq: 3)
    ]

    # Find the instructor map seeded in the loop above for this assignment
    instructor_participant = AssignmentParticipant.find_by!(
      parent_id: full_demo_assignment.id,
      user_id:   instructor.id
    )
    submitter_user = User.find_by!(name: "calibration_submitter_#{full_demo_assignment.id}")
    submitter_participant = AssignmentParticipant.find_by!(
      parent_id: full_demo_assignment.id,
      user_id:   submitter_user.id
    )
    reviewee_team = AssignmentTeam.team(submitter_participant)

    instructor_map = ReviewResponseMap.find_or_create_by!(
      reviewed_object_id: full_demo_assignment.id,
      reviewer_id:        instructor_participant.id,
      reviewee_id:        reviewee_team.id,
      for_calibration:    true
    )

    upsert_response.call(
      map: instructor_map,
      scores: { items[0] => 4, items[1] => 5, items[2] => 3 }
    )

    score_sets = [[4, 5, 3], [4, 4, 3], [4, 4, 2], [3, 4, 1], [3, 2, 1], [1, 1, 0]]

    student_maps = score_sets.each_with_index.map do |scores, index|
      student = ensure_user.call(
        model_class: User,
        name: "calibration_demo_student_#{index + 1}",
        email: "calibration_demo_student_#{index + 1}@example.com",
        role_name: 'Student',
        full_name: "Calibration Demo Student #{index + 1}",
        parent: instructor
      )

      participant = AssignmentParticipant.find_or_create_by!(
        parent_id: full_demo_assignment.id,
        user_id:   student.id
      ) { |p| p.handle = student.name }

      map = ReviewResponseMap.find_or_create_by!(
        reviewed_object_id: full_demo_assignment.id,
        reviewer_id:        participant.id,
        reviewee_id:        reviewee_team.id,
        for_calibration:    true
      )

      upsert_response.call(map: map, scores: { items[0] => scores[0], items[1] => scores[1], items[2] => scores[2] })
      map
    end

    puts({
      full_report_assignment_id: full_demo_assignment.id,
      instructor_map_id:         instructor_map.id,
      reviewee_team_id:          reviewee_team.id,
      student_count:             student_maps.length,
      rubric_items:              items.map(&:txt),
      report_url:                "http://localhost:3000/assignments/edit/#{full_demo_assignment.id}/calibration/#{instructor_map.id}"
    }.inspect)
  end
end
