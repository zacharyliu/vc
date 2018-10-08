if Rails.application.drfvote?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins '*' # TODO(zliu): specify CORS origin
      resource '*', headers: :any, methods: :any
    end
  end
end
