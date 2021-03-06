# Web controller. Provides authenticated actions for use by administrators.
class AdminController < ApplicationController
  before_action :verify_admin
  before_action :verify_global_admin, only: [:admin_email, :send_admin_email, :hellban]

  def index; end

  def error_reports
    @reports = if params[:uuid].present?
                 ErrorLog.where(uuid: params[:uuid])
               elsif current_user.is_global_admin
                 ErrorLog.all
               else
                 ErrorLog.where(community: RequestContext.community)
               end.order(created_at: :desc).paginate(page: params[:page], per_page: 50)
  end

  def privileges
    @privileges = Privilege.all.user_sort({ term: params[:sort], default: :threshold },
                                          rep: :threshold, name: :name)
                           .paginate(page: params[:page], per_page: 20)
  end

  def show_privilege
    @privilege = Privilege.find_by name: params[:name]
    respond_to do |format|
      format.json { render json: @privilege }
    end
  end

  def update_privilege
    @privilege = Privilege.find_by name: params[:name]
    pre = @privilege.threshold
    @privilege.update(threshold: params[:threshold]) &&
      AuditLog.admin_audit(event_type: 'privilege_threshold_update', related: @privilege, user: current_user,
                           comment: "from <<#{pre}>>\nto <<#{params[:threshold]}>>")
    render json: { status: 'OK', privilege: @privilege }, status: 202
  end

  def admin_email; end

  def send_admin_email
    Thread.new do
      AdminMailer.with(body_markdown: params[:body_markdown], subject: params[:subject]).to_moderators.deliver_now
    end
    AuditLog.admin_audit(event_type: 'send_admin_email', user: current_user,
                         comment: "Subject: #{params[:subject]}")
    flash[:success] = t 'admin.email_being_sent'
    redirect_to admin_path
  end

  def audit_log
    @logs = if current_user.is_global_admin
              AuditLog.unscoped.where.not(log_type: ['user_annotation', 'user_history'])
            else
              AuditLog.where.not(log_type: ['block_log', 'user_annotation', 'user_history'])
            end.user_sort({ term: params[:sort], default: :created_at },
                          age: :created_at, type: :log_type, event: :event_type,
                          related: Arel.sql('related_type DESC, related_id DESC'), user: :user_id)
            .paginate(page: params[:page], per_page: 100)
    render layout: 'without_sidebar'
  end

  def hellban
    @user = User.find params[:id]
    @user.block("user manually blocked by admin ##{current_user.id}")
    flash[:success] = t 'admin.user_fed_stat'
    redirect_back fallback_location: admin_path
  end
end
