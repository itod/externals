#!/usr/bin/env ruby
$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'externals/ext'

Externals::Ext.run(*ARGV)
