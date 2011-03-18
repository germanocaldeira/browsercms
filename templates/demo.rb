# Remove the file on both *unix and Windows
if Gem.win_platform?
  run "del public\\index.html"
  run "db/seeds.rb"
else
  run "rm public/index.html"
  run 'rm db/seeds.rb'
end

# Loads the version, so we can explicitly set in the generated cms project.
template_root = File.dirname(__FILE__)
require File.join(template_root, '..', 'lib', 'cms', 'version.rb')
gem "browsercms", :version=>Cms::VERSION

generate :jdbc if defined?(JRUBY_VERSION)

if Gem.win_platform?
  puts "        rake  db:create"
  `rake.cmd db:create`
else
  rake "db:create"
end

generate "browser_cms:cms"

environment 'SITE_DOMAIN="localhost:3000"', :env => "development"
environment 'SITE_DOMAIN="localhost:3000"', :env => "test"
environment 'SITE_DOMAIN="localhost:3000"', :env => "production"
environment 'config.action_view.cache_template_loading = false', :env => "production"
environment 'config.action_controller.page_cache_directory = Rails.root + "/public/cache/"', :env => "production"
generate "browser_cms:demo_site"

require File.join(template_root, '..', 'app', 'models', 'templates.rb')
file 'app/views/layouts/templates/default.html.erb', Templates.default_body

if Gem.win_platform?
  puts "        rake  db:migrate"
  `rake.cmd db:migrate`
  `rake.cmd db:seed`
  `rake.cmd db:seed_demo_site`
else
  rake "db:migrate"
  rake "db:seed"
  rake "db:seed_demo_site"
end

#add routes after demo generation - otherwise there are weird errors
route "routes_for_browser_cms"