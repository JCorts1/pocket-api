Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # This should be the address of your React frontend
    origins 'http://localhost:5173'

    resource '*',
      headers: :any,
      # IMPORTANT: You need to expose the 'Authorization' header
      expose: ['Authorization'],
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
