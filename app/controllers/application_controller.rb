class ApplicationController < ActionController::API
  # Add these lines below
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    # For sign up, allow the :name parameter
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
  end
end
