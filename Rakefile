# encoding: UTF-8

require 'colorize'
require 'shell-spinner'
require 'tty'

def msg(text)
  puts "\n\n"
  ttable = TTY::Table.new
  ttable << [text]
  renderer = TTY::Table::Renderer::Unicode.new(ttable)
  renderer.border.style = :red
  puts renderer.render
end

namespace :swarm do
  namespace :create do
    desc "Create VPC (private network partition)"
    task :vpc do
      ShellSpinner "Creating the VPC (private network partition)" do
      end
    end
  end
end
