module Paginatable
  extend ActiveSupport::Concern

  private

  def paginate(scope)
    page = [ params.fetch(:page, 1).to_i, 1 ].max
    per_page = [ params.fetch(:per_page, 20).to_i, 1 ].max
    per_page = [ per_page, 100 ].min

    total_count = scope.count
    total_pages = (total_count.to_f / per_page).ceil
    records = scope.offset((page - 1) * per_page).limit(per_page)

    [
      records,
      {
        current_page: page,
        total_pages: total_pages.zero? ? 1 : total_pages,
        total_count: total_count,
        per_page: per_page
      }
    ]
  end
end
