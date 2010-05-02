#!/usr/bin/env ruby

require 'rubygems'
require 'sqlite3'
require 'cgi'


############################################################
# Configuration
############################################################

BASE_DIR = File.expand_path("~/Library/Application Support/MobileSync/Backup")
SMS_DB   = "3d0d7e5fb2ce288813306e4d4636395e047a3d28.mddata"


############################################################
# Helper Functions
############################################################

def usage
  puts "\nUsage: iphone-sms-log.rb <10-digit-phone>\n"
  exit -1
end

def phone_permutations(ten_digit_num)
  area_code = ten_digit_num[0,3]
  prefix    = ten_digit_num[3,3]
  suffix    = ten_digit_num[6,4]

  [
    "'#{area_code}#{prefix}#{suffix}'",
    "'1#{area_code}#{prefix}#{suffix}'",
    "'+1#{area_code}#{prefix}#{suffix}'",
    "'(#{area_code}) #{prefix}-#{suffix}'",
    "'1 (#{area_code}) #{prefix}-#{suffix}'",
    "'+1 (#{area_code}) #{prefix}-#{suffix}'",
  ].join(',')
end

def normalize_phone(phone)
  if phone =~ /^(\+)?1?(\d{3})(\d{3})(\d{4})$/
    $2 + $3 + $4
  else
    phone
  end
end


############################################################
# Main Program
############################################################

messages = {}

sql = "SELECT * FROM message"
if ARGV.size > 0
  if ARGV[0] !~ /^\d{10}$/
    usage
  end
  sql << " WHERE address IN (#{phone_permutations(ARGV[0])}) "
end

# NOTE: We're going to read from every directory here. This represents
#       each different devices that is backed up here. We *could* just
#       read into one of them if we wanted. These directories are named
#       by the UDIDs of the devices.
Dir.foreach(BASE_DIR) do |entry|
  next if entry !~ /^[0-9a-f]{40}$/
  smsdb = File.expand_path(SMS_DB, BASE_DIR + "/#{entry}")
  next if !File.exist?(smsdb)
  
  db = SQLite3::Database.new(smsdb)
  db.results_as_hash = true
  db.execute(sql) do |row|
    phonenum = normalize_phone(row['address'])
    mesg = {
      :id        => row['ROWID'],
      :phonenum  => phonenum,
      :direction => case row['flags']
                    when '2' then :incoming
                    when '3' then :outgoing
                    else          :unknown
                    end,
      :text      => row['text'],
      :timestamp => Time.at(row['date'].to_i)
    }
    
    mesgs = messages[phonenum] || []
    if !mesgs.any?{|m| m[:id] == row['ROWID']}
      messages.update(phonenum => (mesgs + [mesg]))
    end
  end
end

puts <<EOT
<html>
<head><title>iPhone SMS Log</title></head>
<body>
EOT

messages.each_pair do |phonenum, mesgs|
  puts "<hr/><table border='1'>"
  puts "<tr><th colspan='2'>SMS Log For #{phonenum}</td></th>"
  puts "<tr><th>#{phonenum}</th><th>Me</th></tr>"
  mesgs.sort!{|x,y| x[:timestamp] <=> y[:timestamp]}
  mesgs.each do |mesg|
    puts "<tr>"
    if mesg[:direction] == :outgoing
      puts "<td>&nbsp;</td>"
    end
    puts "<td><b>#{mesg[:timestamp].strftime('%Y-%m-%d %H:%M:%S')}</b>"
    puts "<br/></br>"
    puts mesg[:text] ? CGI::escapeHTML(mesg[:text]) : "nil"
    puts "</td>"
    if mesg[:direction] == :incoming
      puts "<td>&nbsp;</td>"
    end
    puts "</tr>"
  end
  puts "</table>"
end

puts <<EOT
</body></html>
EOT
