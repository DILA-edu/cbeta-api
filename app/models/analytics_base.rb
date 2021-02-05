class AnalyticsBase < ApplicationRecord
  self.abstract_class = true
  connects_to database: { writing: :analytics, reading: :analytics }
end
