module Api
  module V1
    class EventsController < ApiV1Controller
      before_action :authenticate_api_user!

      def show
        render json: { event: event }
      end

      def update
        event.add_notes! params[:notes]
        head :ok
      end

      private

      def event
        @event ||= CalendarEvent.find(params[:id])
      end
    end
  end
end
