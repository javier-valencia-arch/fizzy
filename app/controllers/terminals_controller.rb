class TerminalsController < ApplicationController
  def show
    @events = Event.where(card: Current.user.accessible_cards, creator: Current.user).chronologically.reverse_order.limit(20)
  end

  def edit
    @filter = Current.user.filters.from_params params.permit(*Filter::PERMITTED_PARAMS)
  end
end
