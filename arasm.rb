#!/usr/bin/env ruby

$cmdlist	= []
$blocks 	= {}
$out			= ""
$help			= "USAGE: arasm <-f file> [ -o outfile ]"
$options 	= {}

ARGV.each_with_index do |i,ind|
	case i
	when "-f"
		$options["file"] = ARGV[ind+1]
	when "-o"
		$options["outfile"] = ARGV[ind+1]
	end
end

unless $options["file"]
	abort $help
end

content = File.read($options["file"]).split("\n") rescue abort($help)
content.map!{|i|i.match(/;/) ? i.strip.split(";")[0].strip : i}
#content.select!{|i|!i.empty?}

def abort_with_style(l,i,e)
	i.to_s.match(/^[0-9]+$/)&&i+=1
	abort("[#{i}]FATAL @ `#{l}`: #{e}")
end

valid_commands = %w( mv[dwb] [dw]lt [dw]gt [dw]eq [dw]ne [lsa]of rop [as]st si[dwb] ls[dwb] fmv fcp ).map{|i|eval("/^"+i+"/i")}

def assert_args(com,ln,*types)
	com.is_a?(Array)||com=com.split
	com.length-1==types.length||abort_with_style(com.join(" "),ln,"WRONG NUMBER OF ARGUMENTS, EXPECTED #{types.length}, GOT #{com.length-1}.")
	type_rxps = {
		/\.[^\s;]+/ 		=> :block,
		/\$[A-Z0-9]+/i 	=> :num,
		/[0-9]+/i 			=> :num,
		/.*/						=> :some_weird_alphanumeric_foo
	}
	types.each{|i|type_rxps.values.include?(i)||raise("Unknown literal type #{i.inspect}")}
	com[1..-1].each_with_index do |i,ind|
		identifier = type_rxps[type_rxps.keys.select{|k|i.match(k)}[0]]
		identifier==types[ind]||abort_with_style(com.join(" "),ln,"ARGUMENT #{ind+1} HAS WRONG TYPE, EXPECTED #{types[ind]}, GOT #{identifier} INSTEAD.")
	end
end

def parse_command(c,ln)
	barr_t = ""
	command = c.split

	case command[0]

	when /^mv[dwb]$/
		assert_args(c,ln,:num,:num)
		barr_t << %w(d w b).index(command[0][2]).to_s
		addr = (command[1][0]==?$ ? sprintf("%07x",command[1][1..-1].to_i(16)) : sprintf("%07x",command[1].to_i))
		val= (command[2][0]==?$ ? sprintf("%08x",command[2][1..-1].to_i(16)) : sprintf("%08x",command[2].to_i))
		#puts "MV with addr=#{addr.inspect} val=#{val.inspect}"
		barr_t << addr << val

	when /^[dw]lt$/
		assert_args(c,ln,:num,:num,:block)
		barr_t << ( 3 + 4*%w(d w).index(command[0][0]) ).to_s(16)
		addr   = (command[1][0]==?$ ? sprintf("%07x",command[1][1..-1].to_i(16)) : sprintf("%07x",command[1].to_i))
		val    = (command[2][0]==?$ ? sprintf("%08x",command[2][1..-1].to_i(16)) : sprintf("%08x",command[2].to_i))
		block  = command[3][1..-1]
		$blocks[block] = "if"
		barr_t << addr << val

	when /^[dw]gt$/
		assert_args(c,ln,:num,:num,:block)
		barr_t << ( 4 + 4*%w(d w).index(command[0][0]) ).to_s(16)
		addr   = (command[1][0]==?$ ? sprintf("%07x",command[1][1..-1].to_i(16)) : sprintf("%07x",command[1].to_i))
		val    = (command[2][0]==?$ ? sprintf("%08x",command[2][1..-1].to_i(16)) : sprintf("%08x",command[2].to_i))
		block  = command[3][1..-1]
		$blocks[block] = "if"
		barr_t << addr << val

	when /^[dw]eq$/
		assert_args(c,ln,:num,:num,:block)
		barr_t << ( 5 + 4*%w(d w).index(command[0][0]) ).to_s(16)
		addr   = (command[1][0]==?$ ? sprintf("%07x",command[1][1..-1].to_i(16)) : sprintf("%07x",command[1].to_i))
		val    = (command[2][0]==?$ ? sprintf("%08x",command[2][1..-1].to_i(16)) : sprintf("%08x",command[2].to_i))
		block  = command[3][1..-1]
		$blocks[block] = "if"
		barr_t << addr << val

	when /^[dw]ne$/
		assert_args(c,ln,:num,:num,:block)
		barr_t << ( 6 + 4*%w(d w).index(command[0][0]) ).to_s(16)
		x_addr = (command[1][0]==?$ ? sprintf("%07x",command[1][1..-1].to_i(16)) : sprintf("%07x",command[1].to_i))
		val    = (command[2][0]==?$ ? sprintf("%08x",command[2][1..-1].to_i(16)) : sprintf("%08x",command[2].to_i))
		block  = command[3][1..-1]
		$blocks[block] = "if"
		#p {x_addr: x, val: val,}
		barr_t << addr << val

	when "lof"
		assert_args(c,ln,:num)
		addr = (command[1][0]==?$ ? sprintf("%07x",command[1][1..-1].to_i(16)) : sprintf("%07x",command[1].to_i))
		barr_t << "b" << addr << "00000000"

	when "rop"
		assert_args(c,ln,:num,:block)
		$rop&&abort_with_style(c,ln,"NESTING ROP BLOCKS IS PROHIBITED.")
		$rop  = ln
		t     = (command[1][0]==?$ ? sprintf("%08x",command[1][1..-1].to_i(16)) : sprintf("%08x",command[1].to_i))
		block = command[2][1..-1]
		$blocks[block] = "rop"
		barr_t << "c0000000" << t

	when /^~/
		bname = command[0][1..-1]
		bname==?#||$blocks[bname]||abort_with_style(c,ln,"TRYING TO CLOSE BLOCK `#{bname}` WHICH WASN'T OPENED BEFORE.")
		if bname == ?#
			barr_t << "d2" << ("0"*14)
		elsif $blocks[bname] == "if"
			barr_t << "d0" << ("0"*14)
		else
			barr_t << "d1" << ("0"*14)
			$rop = nil
		end
		$blocks.delete(bname)

	when "sof"
		assert_args(c,ln,:num)
		val = (command[1][0]==?$ ? sprintf("%08x",command[1][1..-1].to_i(16)) : sprintf("%08x",command[1].to_i))
		barr_t << "d3000000" << val

	when "ast"
		assert_args(c,ln,:num)
		val = (command[1][0]==?$ ? sprintf("%08x",command[1][1..-1].to_i(16)) : sprintf("%08x",command[1].to_i))
		barr_t << "d4000000" << val

	when "sst"
		assert_args(c,ln,:num)
		val = (command[1][0]==?$ ? sprintf("%08x",command[1][1..-1].to_i(16)) : sprintf("%08x",command[1].to_i))
		barr_t << "d5000000" << val

	when /si[dwb]/
		assert_args(c,ln,:num)
		barr_t << "d" << (6+%w(d w b).index).to_s(16) << ("0"*6)
		addr = (command[1][0]==?$ ? sprintf("%08x",command[1][1..-1].to_i(16)) : sprintf("%08x",command[1].to_i))
		barr_t << val

	when /ls[dwb]/
		assert_args(c,ln,:num)
		barr_t << "d" << (9+%w(d w b).index).to_s(16) << ("0"*6)
		addr = (command[1][0]==?$ ? sprintf("%08x",command[1][1..-1].to_i(16)) : sprintf("%08x",command[1].to_i))
		barr_t << val

	when "aof"
		assert_args(c,ln,:num)
		barr_t << "dc" << ("0"*6)
		val = (command[1][0]==?$ ? sprintf("%08x",command[1][1..-1].to_i(16)) : sprintf("%08x",command[1].to_i))
		barr_t << val

	when "fmv"
		abort_with_style(c,ln,"FMV IS NOT IMPLEMENTED YET.")
		assert_args(c,ln,:num,:num,:num)
		barr_t << "e"
		addr_s    = (command[1][0]==?$ ?  sprintf("%07x",command[1][1..-1].to_i(16)) :  sprintf("%07x",command[1].to_i))
		vals      = (command[2][0]==?$ ? sprintf("%016x",command[2][1..-1].to_i(16)) : sprintf("%016x",command[2].to_i))
		num_b     = (command[3][0]==?$ ?  sprintf("%08x",command[1][1..-1].to_i(16)) :  sprintf("%08x",command[1].to_i))
		barr_t << addr_s << num_b << vals

	when "fcp"
		assert_args(c,ln,:num,:num)
		addr_s = (command[1][0]==?$ ? sprintf("%07x",command[1][1..-1].to_i(16)) : sprintf("%07x",command[1].to_i))
		length = (command[1][0]==?$ ? sprintf("%08x",command[1][1..-1].to_i(16)) : sprintf("%08x",command[1].to_i))
		barr_t << addr_s << length

	end

	return barr_t

end

content.each_with_index do |i,ind|
	$out << parse_command(i,ind)
end

unless $blocks.empty?
	abort("FATAL @ EOF: THE FOLLOWING BLOCKS WEREN'T CLOSED. #{$blocks.keys.join(" ")}")
end

$out = $out.split("")
($out.length/2).times do
	$out << $out.shift(2).join.to_i(16).chr
end

$options["outfile"] ||= $options["file"].split(?.)[0..-2].join(?.)+".cht"

File.write($options["outfile"],$out.join)
