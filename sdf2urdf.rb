#!/usr/bin/ruby

require 'nokogiri'

def convert_pose(parent, builder)
  sdf_pose = parent.>("pose").first
  return if sdf_pose.nil?

  origin = builder.origin
  tokens = sdf_pose.text.split
  if not tokens.all? {|x| x.to_f == 0 }
    origin['xyz'] = tokens[0,3].join(" ")
    origin['rpy'] = tokens[3,3].join(" ")
  end
end

def convert_geometry(parent, builder)
  parent.>("geometry").each do |sdf_geom|
    builder.geometry {
      sdf_geom.element_children.each do |sdf_prim|
        attrs = {}
        sdf_prim.element_children.each do |param|
          attrs[param.name] = param.text
        end
        
        builder.send(sdf_prim.name, attrs)
      end
    }
  end
end

def convert_links(parent, out)
  parent.>('link').each do |sdf_link|
    out.link(:name => sdf_link[:name]) {

      sdf_link.xpath('/visual').each do |sdf_visual|
        out.visual {
          convert_pose(sdf_visual, out)
          convert_geometry(sdf_visual, out)
        }
      end

      if sdf_inertial = sdf_link.>("inertial").first
        out.inertial {
          convert_pose(sdf_inertial, out)
          
          if sdf_mass = sdf_inertial.>("mass").first
            out.mass(:value => sdf_mass.text)
          end
          
          if sdf_inertia = sdf_inertial.>("inertia").first
            attrs = {}
            sdf_inertia.element_children.each do |item|
              attrs[item.name] = item.text # if item.name =~ /^i[xyz][xyz]$/
            end
            out.inertia(attrs)
          end
        }
      end

      sdf_link.>("collision").each do |sdf_collision|
        out.collision {
          convert_pose(sdf_collision, out)
          convert_geometry(sdf_collision, out)
        }
      end # do |sdf_visual|
    } # out.link
  end # do |sdf_link|
end

def flatten_tag(builder, in_parent, out_tag, bindings)
  attrs = {}
  bindings.each do |xpath, out_attr|
    if child = in_parent.at_xpath(xpath) 
      attrs[out_attr] = child.text
    end
  end
  
  builder.method_missing(out_tag, attrs) unless attrs == {}
end

URDF_VALID_JOINTS = "revolute continuous prismatic fixed floating planar".split
def convert_joints(parent, out)
  parent.>("joint").each do |sdf_joint|
    if not URDF_VALID_JOINTS.include? sdf_joint[:type]
      warn "URDF does not support joint type `#{sdf_joint[:type]}'"
    else
      out.joint(:name => sdf_joint[:name], :type => sdf_joint[:type]) {
        convert_pose(sdf_joint, out)

        flatten_tag(out, sdf_joint, "child", "child" => :link)
        flatten_tag(out, sdf_joint, "parent", "parent" => :link)
        flatten_tag(out, sdf_joint, "axis", "xyz" => :xyz)
        flatten_tag(out, sdf_joint, "dynamic", 
                    "axis/dynamic/damping" => :damping,
                    "axis/dynamic/friction" => :friction)

        flatten_tag(out, sdf_joint, "limit",
                    "axis/limit/lower"    => :lower,
                    "axis/limit/upper"    => :upper,
                    "axis/limit/effort"   => :effort,
                    "axis/limit/velocity" => :velocity)
      }  
    end
  end
end

## Input
input_f = ARGV.length > 0 ? File.open(ARGV[0]) : STDIN 
input = Nokogiri::XML(input_f)
abort("root element is not <sdf>, but <#{input.root.name}>") unless input.root.name == "sdf"

model = input.at_xpath('/sdf/model')
abort("No <model> tag") if model.nil?

STDERR.puts "Robot name: `#{model[:name]}'"

## Output
builder = Nokogiri::XML::Builder.new do |out|
  out.robot(:name => model[:name]) {
    convert_links(model, out)
    convert_joints(model, out)
  } # out.robot
end # do |out|

puts builder.to_xml

