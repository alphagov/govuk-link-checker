FactoryGirl.define do
  factory :check do
    started_at "2017-04-03 15:36:31"
    ended_at "2017-04-03 15:36:35"
    link_warnings Hash.new
    link_errors Hash.new
  end
end
