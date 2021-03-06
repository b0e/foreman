class UsersController < ApplicationController
  include Foreman::Controller::AutoCompleteSearch
  include Foreman::Controller::UsersMixin

  before_filter :find_resource, :only => [:edit, :update, :destroy]
  skip_before_filter :require_mail, :only => [:edit, :update, :logout]
  skip_before_filter :require_login, :authorize, :session_expiry, :update_activity_time, :set_taxonomy, :set_gettext_locale_db, :only => [:login, :logout, :extlogout]
  skip_before_filter :authorize, :only => :extlogin
  after_filter       :update_activity_time, :only => :login

  def index
    @users = User.search_for(params[:search], :order => params[:order]).includes(:auth_source).paginate(:page => params[:page])
  end

  def new
    @user = User.new
  end

  def create
    if @user.save
      process_success
    else
      process_error
    end
  end

  def edit
    editing_self?
    if @user.user_facts.count == 0
      user_fact = @user.user_facts.build :operator => "==", :andor => "or"
      user_fact.fact_name_id = FactName.first.id if FactName.first
    end
  end

  def update
    if @user.update_attributes(params[:user])
      update_sub_hostgroups_owners

      process_success((editing_self? && !current_user.allowed_to?({:controller => 'users', :action => 'index'})) ? { :success_redirect => hosts_path } : {})
    else
      process_error
    end
  end

  def destroy
    if @user == User.current
      notice _("You are currently logged in, suicidal?")
      redirect_to :back and return
    end
    if @user.destroy
      process_success
    else
      process_error
    end
  end

  # Called from the login form.
  # Stores the user id in the session and redirects required URL or default homepage
  def login
    User.current = nil
    if request.post?
      backup_session_content { reset_session }
      user = User.try_to_login(params[:login]['login'].downcase, params[:login]['password'])
      if user.nil?
        #failed to authenticate, and/or to generate the account on the fly
        error _("Incorrect username or password")
        redirect_to login_users_path
      else
        #valid user
        login_user(user)
      end
    else
      if params[:status] && params[:status] == 401
        render :layout => 'login', :status => params[:status]
      else
        render :layout => 'login'
      end
    end
  end

  def extlogin
    if session[:user]
      user = User.find_by_id(session[:user])
      login_user(user)
    end
  end

  # Called from the logout link
  # Clears the rails session and redirects to the login action
  def logout
    TopbarSweeper.expire_cache(self)
    sso_logout_path = get_sso_method.try(:logout_url)
    session[:user] = @user = User.current = nil
    if flash[:notice] or flash[:error]
      flash.keep
    else
      session.clear
      notice _("Logged out - See you soon")
    end
    redirect_to sso_logout_path || login_users_path
  end

  def extlogout
    render :extlogout, :layout => 'login'
  end

  private

  def find_resource
    @user ||= User.find(params[:id])
  end

  def login_user(user)
    session[:user]         = user.id
    uri                    = session[:original_uri]
    session[:original_uri] = nil
    redirect_to (uri || hosts_path)
  end

end
