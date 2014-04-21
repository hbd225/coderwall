class AccountsController < ApplicationController
  layout 'product_description'
  skip_before_filter :verify_authenticity_token, only: [:webhook]
  before_filter :lookup_account, except: [:webhook, :send_invoice]
  before_filter :ensure_account_admin, except: [:create]
  before_filter :determine_plan, only: [:create, :update]
  before_filter :ensure_eligibility, only: [:new]
  before_filter :paying_user_context, if: ->() { Rails.env.production? }

  def new
    @account ||= current_user.team.build_account
    @plan    = params[:public_id]
  end

  def create
    redirect_to teamname_path(slug: @team.slug) if @plan.free?

    @account           = @team.build_account(params[:account])
    @account.admin_id  = current_user.id
    @account.trial_end = Date.new(2013, 1, 1).to_time.to_i if session[:discount] == ENV['DISCOUNT_TOKEN']

    if @account.save_with_payment(@plan)
      unless @team.is_member?(current_user)
        @team.add_user(current_user)
        @team.save
      end
      record_event('upgraded team')

      Subscription.team_upgrade(current_user.username, @plan.id).deliver
      redirect_to new_team_opportunity_path(@team), notice: "You are subscribed to #{@plan.name}." + plan_capability(@plan, @team)
    else
      puts "Error creating account #{@account.errors.inspect}"
      Honeybadger.notify(error_class: 'Payments', error_message: @account.errors.full_messages.join("\n"), parameters: params) if Rails.env.production?
      flash[:error] = @account.errors.full_messages.join("\n")
      redirect_to employers_path
    end
  end

  def update
    if @account.update_attributes(params[:account]) && @account.save_with_payment(@plan)
      redirect_to new_team_opportunity_path(@team), notice: "You are subscribed to #{@plan.name}." + plan_capability(@plan, @team)
    else
      flash[:error] = @account.errors.full_messages.join("\n")
      redirect_to employers_path
    end
  end

  def webhook
    data = JSON.parse request.body.read
    if data[:type] == "invoice.payment_succeeded"
      invoice_id  = data['data']['object']['id']
      customer_id = data['data']['object']['customer']
      team        = Team.where('account.stripe_customer_token' => customer_id).first

      unless data['paid']
        team.account.suspend!
      else
        team.account.send_invoice(invoice_id)
      end
    end
  end

  def send_invoice
    @team = Team.find(params[:team_id])
    @team.account.send_invoice_for(1.month.ago)
    redirect_to teamname_path(slug: @team.slug), notice: "sent invoice for #{1.month.ago.strftime("%B")} to #{@team.account.admin.email}"
  end

  private
  def lookup_account
    @team = (current_user && current_user.team) || (params[:team_id] && Team.find(params[:team_id]))
    return redirect_to employers_path if @team.nil?
    @account = @team.account
  end

  def ensure_account_admin
    is_admin? || current_user.team && current_user.team.admin?(current_user)
  end

  def determine_plan
    chosen_plan = params[:account].delete(:chosen_plan)
    @plan       = Plan.find_by_public_id(chosen_plan)
  end

  def ensure_eligibility
    return redirect_to(teamname_path(@team.slug), notice: "you must complete at least 6 sections of the team profile before posting jobs") unless @team.has_specified_enough_info?
  end

  def plan_capability(plan, team)
    message = ""
    if plan.subscription?
      message = "You can now post up to #{team.number_of_jobs_to_show} jobs at any time"
    elsif plan.one_time?
      message = "You can now post one job for 30 days"
    end
    message
  end

  def paying_user_context
    Honeybadger.context(user_email: current_user.try(:email)) if current_user
  end

end
