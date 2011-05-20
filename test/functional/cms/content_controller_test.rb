require 'test_helper'

module Cms
class ContentControllerTest < ActionController::TestCase
  include Cms::ControllerTestHelper

  def test_show_home_page
    get :show
    assert_response :success
    assert_select "title", "Home"
  end

  def test_show_another_page
    @page = Factory(:page, :section => root_section, :path => "/about", :name => "Test About", :template_file_name => "default.html.erb", :publish_on_save => true)
    get :show, :path => "about"
    assert_select "title", "Test About"
  end

  def test_page_not_found_to_guest
    get :show, :path => "foo"
    assert_response :not_found
    assert_select "title", "Not Found"
    assert_select "h1", "Page Not Found"
  end

  def test_page_not_found_to_cms_admin
    login_as_cms_admin
    get :show, :path => "foo"
    assert_response :not_found
    assert_select "title", "Page Not Found"
    assert_select "h2", "There is no page at /foo"
  end

  def test_show_protected_page_to_guest
    create_protected_page

    get :show, :path => "secret"
    assert_response :forbidden
    assert_select "title", "Access Denied"
  end

  def test_show_protected_page_to_privileged_user
    create_protected_page

    login_as @privileged_user

    get :show, :path => "secret"
    assert_response :success
    assert_select "title", "Shhh... It's a Secret"
  end

  def test_show_archived_page_to_guest
    create_archived_page

    get :show, :path => "archived"
    assert_response :not_found
    assert_select "title", "Not Found"
  end

  def test_show_archived_page_to_user
    create_archived_page
    login_as_cms_admin

    get :show, :path => "archived"
    assert_response :success
    assert_select "title", "Archived"
  end

  def test_show_file
    create_file

    @controller.expects(:send_file).with(@file_block.attachment.full_file_location, :filename => 'test.txt', :type => 'text/plain',:disposition => "inline")

    get :show, :path => "test.txt"
  end

  def test_show_archived_file
    create_file

    reset(:file_block)
    @file_block.update_attributes(:archived => true, :publish_on_save => true)
    reset(:file_block)
    assert @file_block.attachment.archived?

    get :show, :path => "test.txt"

    assert_response :not_found
    assert_select "title", "Not Found"
  end

  def test_show_protected_file_to_guest
    create_protected_file

    get :show, :path => "test.txt"

    assert_response :forbidden
    assert_select "title", "Access Denied"
  end

  def test_show_protected_file_to_privileged_user
    create_protected_file
    login_as @privileged_user
    @controller.expects(:send_file).with(@file_block.attachment.full_file_location, :filename => 'test.txt', :type => 'text/plain',:disposition => "inline")

    get :show, :path => "test.txt"

  end

  def test_show_page_route
    @page_template = Factory(:page_template, :name => "test_show_page_route")
    @page = Factory(:page,
      :section => root_section,
      :template_file_name => "test_show_page_route.html.erb")
    @portlet = DynamicPortlet.create!(:name => "Test",
      :template => "<h1><%= @foo %></h1>",
      :connect_to_page_id => @page.id, :connect_to_container => "main")
    @page_route = @page.page_routes.create(:pattern => "/foo", :code => "@foo = params[:foo]")

    reset(:page)
    @page.publish!

    get :show_page_route, :foo => "42", :_page_route_id => @page_route.id
    assert_response :success
    assert_select "h1", "42"
  end

  def test_show_page_with_content
    create_page_with_content
    get :show, :path => "page_with_content"
    assert_response :success
    assert_select "h3", "TEST"
  end

  def test_show_draft_page_with_content_as_editor
    login_as_cms_admin
    create_page_with_content

    @block.update_attributes(:content => "<h3>I've been edited</h3>")
    reset(:page, :block)

    get :show, :path => "page_with_content"
    assert_response :success
    assert_select "h3", "I've been edited"
  end



  protected
    def create_protected_user_section_group
      @protected_section = Factory(:section, :parent => root_section)
      @secret_group = Factory(:group, :name => "Secret")
      @secret_group.sections << @protected_section
      @privileged_user = Factory(:user, :login => "privileged")
      @privileged_user.groups << @secret_group
    end

    def create_protected_page
      create_protected_user_section_group
      @page = Factory(:page,
        :section => @protected_section,
        :path => "/secret",
        :name => "Shhh... It's a Secret",
        :template_file_name => "default.html.erb",
        :publish_on_save => true)
    end

    def create_file
      @file = mock_file(:content_type => "text/plain")
      @file_block = Factory(:file_block, :attachment_section => root_section, :attachment_file => @file, :attachment_file_path => "/test.txt", :publish_on_save => true)
    end

    def create_protected_file
      create_protected_user_section_group
      create_file
      reset(:file_block)
      @file_block.update_attributes(:attachment_section => @protected_section)
      reset(:file_block)
    end

    def create_archived_page
      @page = Factory(:page,
        :section => root_section,
        :path => "/archived",
        :name => "Archived",
        :archived => true,
        :template_file_name => "default.html.erb",
        :publish_on_save => true)
    end

    def create_page_with_content
      @page_template = Factory(:page_template, :name => "testing_editting_content")

      @page = Factory(:page,
        :section => root_section,
        :path => "/page_with_content",
        :template_file_name => "testing_editting_content.html.erb")

      @block = HtmlBlock.create!(:name => "Test",
        :content => "<h3>TEST</h3>",
        :connect_to_page_id => @page.id,
        :connect_to_container => "main")

      reset(:page)
      @page.publish!

    end

end

# CMS Page Caching Enabled (Production Mode)
#   Logged in as guest
#         mysite.com/page         -> serves cached page
#     cms.mysite.com/page         -> redirect to mysite.com/page
#
#   Logged in as a registered user
#         mysite.com/page         -> serves cached page
#     cms.mysite.com/page         -> redirect to mysite.com/page
#
#   Logged in as cms user
#         mysite.com/page         -> serves cached page
#     cms.mysite.com/page         -> renders cms page editor
class ContentCachingEnabledControllerTest < ActionController::TestCase
  tests Cms::ContentController
  include Cms::ControllerTestHelper

  def setup
    ActionController::Base.perform_caching = true
    @page = Factory(:page, :section => root_section, :name => "Test Page", :path => "/page", :publish_on_save => true)
    @registered_user = Factory(:user)
    @registered_user.groups << Group.guest
  end

  def teardown
    ActionController::Base.perform_caching = false
  end

  def test_guest_user_views_page_on_public_site
    @request.host = "mysite.com"
    get :show, :path => "page"
    assert_response :success
    assert_select "title", "Test Page"
  end

  def test_guest_user_views_page_on_cms_site
    @request.host = "cms.mysite.com"

    # Actually simulates http://cms.mysite.com/?path=page , but we can't test domains in functional specs
    get :show, :path => "page"

    # Really should go to "http://mysite.com/page" instead.
    assert_redirected_to "http://mysite.com/?path=page"
  end

  def test_registered_user_views_page_on_public_site
    login_as @registered_user
    @request.host = "mysite.com"

    get :show, :path => "page"

    assert_response :success
    assert_select "title", "Test Page"
  end

  def test_registered_user_views_page_on_cms_site
    login_as @registered_user
    @request.host = "cms.mysite.com"

    # Simulates http://cms.mysite.com/?path=page rather than http://cms.mysite.com/page
    get :show, :path => "page"

    assert_redirected_to "http://mysite.com/?path=page"
  end

  def test_cms_user_views_page_on_public_site
    login_as_cms_admin
    @request.session[:page_mode] = "edit"
    @request.host = "mysite.com"

    get :show, :path => "page"

    assert_response :success
    assert_select "title", "Test Page"
    assert_select "iframe", {:count => 0}
  end

  def test_cms_user_views_page_on_cms_site
    login_as_cms_admin
    @request.session[:page_mode] = "edit"
    @request.host = "cms.mysite.com"

    get :show, :path => "page"

    assert_response :success
    assert_select "title", "Test Page"
    assert_select "iframe"
  end

end

# CMS Page Caching Disabled (Development Mode)
#   Logged in as guest
#         mysite.com/page         -> renders page
#     cms.mysite.com/page         -> renders page
#
#   Logged in as a registered user
#         mysite.com/page         -> renders page
#     cms.mysite.com/page         -> renders page
#
#   Logged in as cms user
#         mysite.com/page         -> renders cms page editor
#     cms.mysite.com/page         -> renders cms page editor
class ContentCachingDisabledControllerTest < ActionController::TestCase
  tests Cms::ContentController
  include Cms::ControllerTestHelper

  def setup
    ActionController::Base.perform_caching = false
    @page = Factory(:page, :section => root_section, :name => "Test Page", :path => "/page", :publish_on_save => true)
    @registered_user = Factory(:user)
    @registered_user.groups << Group.guest
  end

  def test_guest_user_views_page_on_public_site
    @request.host = "mysite.com"
    get :show, :path => "page"
    assert_response :success
    assert_select "title", "Test Page"
  end

  def test_guest_user_views_page_on_cms_site
    @request.host = "mysite.com"
    get :show, :path => "page"
    assert_response :success
    assert_select "title", "Test Page"
  end

  def test_registered_user_views_page_on_public_site
    login_as @registered_user
    @request.host = "mysite.com"

    get :show, :path => "page"

    assert_response :success
    assert_select "title", "Test Page"
  end

  def test_registered_user_views_page_on_cms_site
    login_as @registered_user
    @request.host = "mysite.com"

    get :show, :path => "page"

    assert_response :success
    assert_select "title", "Test Page"
  end

  def test_cms_user_views_page_on_public_site
    login_as_cms_admin
    @request.session[:page_mode] = "edit"
    @request.host = "mysite.com"

    get :show, :path => "page"

    assert_response :success
    assert_select "title", "Test Page"
    assert_select "iframe"
  end

  def test_cms_user_views_page_on_cms_site
    login_as_cms_admin
    @request.session[:page_mode] = "edit"
    @request.host = "cms.mysite.com"

    get :show, :path => "page"

    assert_response :success
    assert_select "title", "Test Page"
    assert_select "iframe"
  end

  def test_portlet_throw_access_denied_goes_to_access_denied_page
    @page = Factory(:page, :section => root_section, :path => "/about", :name => "Test About", :template_file_name => "default.html.erb", :publish_on_save => true)
    @portlet_render = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :template => '<p id="hi">hello</p>')
    @portlet_raise_access_denied = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :code => 'raise Cms::Errors::AccessDenied')
    reset(:page)

    get :show, :path => "about"
    assert_response :forbidden
    assert_select "title", "Access Denied"
  end
  def test_portlet_throw_not_found_goes_to_not_found_page
    @page = Factory(:page, :section => root_section, :path => "/about", :name => "Test About", :template_file_name => "default.html.erb", :publish_on_save => true)
    @portlet_render = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :template => '<p id="hi">hello</p>')
    @portlet_raise_not_found = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :code => 'raise ActiveRecord::RecordNotFound')
    reset(:page)

    get :show, :path => "about"
    assert_response :not_found
    assert_select "title", "Not Found"
  end

  def test_portlets_throw_multiple_goes_to_not_found
    @page = Factory(:page, :section => root_section, :path => "/about", :name => "Test About", :template_file_name => "default.html.erb", :publish_on_save => true)
    @portlet_render = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :template => '<p id="hi">hello</p>')
    @portlet_raise_not_found = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :code => 'raise ActiveRecord::RecordNotFound')
    @portlet_raise_access_denied = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :code => 'raise Cms::Errors::AccessDenied')   
    @portlet_raise_generic = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :code => 'raise')
    reset(:page)

    get :show, :path => "about"
    assert_response :not_found
    assert_select "title", "Not Found"
  end

  def test_portlets_throw_multiple_goes_to_access_denied
    @page = Factory(:page, :section => root_section, :path => "/about", :name => "Test About", :template_file_name => "default.html.erb", :publish_on_save => true)
    @portlet_render = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :template => '<p id="hi">hello</p>')
    @portlet_raise_access_denied = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :code => 'raise Cms::Errors::AccessDenied')   
    @portlet_raise_generic = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :code => 'raise')
    reset(:page)

    get :show, :path => "about"
    assert_response :forbidden
    assert_select "title", "Access Denied"
  end

  test "When portlets throw a generic error, the page should still render the other content." do
    @page = Factory(:page, :section => root_section, :path => "/about", :name => "Test About", :template_file_name => "default.html.erb", :publish_on_save => true)
    @portlet_render = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :template => '<p id="hi">hello</p>')
    @portlet_raise_generic = DynamicPortlet.create!(:name => "Test", :connect_to_page_id => @page.id, :connect_to_container => "main", :code => 'raise')
    reset(:page)

    get :show, :path => "about"


    assert_select "#hi", "hello"

  end
end
end
