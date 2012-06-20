require 'sane'

require_relative 'jframe_helper_methods' # jframe stuff gets its own file, it's so much.

module SimpleGuiCreator
  
 include_package 'javax.swing'
 # and use  these constants (bug: http://jira.codehaus.org/browse/JRUBY-5107)
 [JProgressBar, JButton, JLabel, JPanel, JOptionPane,
   JFileChooser, JComboBox, JDialog, SwingUtilities, JSlider, JPasswordField, UIManager] 
   
 include_package 'java.awt'; [Font, FileDialog] 
 
 class JOptionPane
    JOptionReturnValuesTranslator = {0 => :yes, 1 => :no, 2 => :cancel, -1 => :exited}
    
    # accepts :yes => "yes text", :no => "no text"
    # returns  :yes :no :cancel or :exited
    # you must specify text for valid options.
    # example, if you specify :cancel => 'cancel' then it won't raise if they cancel
    # raises if they select cancel or exit, unless you pass in :exited => true as an option
    def self.show_select_buttons_prompt message, names_hash = {}
      names_hash[:yes] ||= 'Yes'
      names_hash[:no] ||= 'No'
      # ok ?
      old = ['no', 'yes', 'ok'].map{|name| 'OptionPane.' + name + 'ButtonText'}.map{|name| [name, UIManager.get(name)]}
      if names_hash[:yes]
        UIManager.put("OptionPane.yesButtonText", names_hash[:yes])
      end
      if names_hash[:no]
        UIManager.put("OptionPane.noButtonText", names_hash[:no])
      end
      # if names_hash[:ok] # ???
      #   UIManager.put("OptionPane.okButtonText", names_hash[:ok])
      # end
      if names_hash[:cancel]
        UIManager.put("OptionPane.noButtonText", names_hash[:cancel])
      end
      title = message.split(' ')[0..5].join(' ')
      returned = JOptionPane.showConfirmDialog SwingHelpers.get_always_on_top_frame, message, title, JOptionPane::YES_NO_CANCEL_OPTION
      SwingHelpers.close_always_on_top_frame
      old.each{|name, old_setting| UIManager.put(name, old_setting)}
      out = JOptionReturnValuesTranslator[returned]
      if !out || !names_hash.key?(out)
        raise 'canceled or exited an option prompt:' + out.to_s + ' ' + message
      end
      out
    end
    
 end

 class JButton
 
   def initialize(*args)
    super(*args)
    set_font Font.new("Tahoma", Font::PLAIN, 11)
   end
  
   def on_clicked &block
     raise unless block # sanity check
     @block = block
     add_action_listener do |e|
       begin
         block.call
       rescue Exception => e
             # e.backtrace[0] == "/Users/rogerdpack/sensible-cinema/lib/gui/create.rb:149:in `setup_create_buttons'"
             bt_out = ""
             for line in e.backtrace[0..1]
               backtrace_pieces = line.split(':')
               backtrace_pieces.shift if OS.doze? # ignore drive letter
	       filename = backtrace_pieces[0].split('/')[-1]
	       line_number =  backtrace_pieces[1]
               bt_out += " #{filename}:#{line_number}" 
             end
         puts 'button cancelled somehow!' + e.to_s + ' ' + get_text[0..50] + bt_out
         if $VERBOSE
          puts "got fatal exception thrown in button [aborted] #{e} #{e.class} #{e.backtrace[0]}"
          puts e.backtrace, e
         end
       end        
     end
     self
   end
  
   def simulate_click
     @block.call
   end
  
   def tool_tip= text
     if text
       text = "<html>" + text + "</html>"
       text = text.gsub("\n", "<br/>")
     end
     self.set_tool_tip_text text   
   end
  
   def enable
    set_enabled true
   end
  
   def disable
    set_enabled false
   end
  
 end

 ToolTipManager.sharedInstance().setDismissDelay(10000) # these are way too fast normally
 
   class JFileChooser
    # also set_current_directory et al...
    
    # raises on failure...
    def go show_save_dialog_instead = false
      if show_save_dialog_instead
        success = show_save_dialog nil
      else
        success = show_open_dialog nil
      end
      unless success == Java::javax::swing::JFileChooser::APPROVE_OPTION
        java.lang.System.exit 1 # kills background proc...but we shouldn't let them do stuff while a background proc is running, anyway
      end
      get_selected_file.get_absolute_path
    end
    
    # match FileDialog methods...
    def set_title x
      set_dialog_title x
    end
    
    def set_file f
      set_selected_file JFile.new(f)
    end
    
    alias setFile set_file
  end


  # awt...the native looking one...
  class FileDialog
    def go
      show
	  dispose # allow app to exit :P
      if get_file 
        # they picked something...
        File.expand_path(get_directory + '/' + get_file)
      else
        nil
      end
    end
  end
 
 
  class NonBlockingDialog < JDialog
    def initialize title_and_display_text, close_button_text = 'Close'
      super nil # so that set_title will work
      lines = title_and_display_text.split("\n")
      set_title lines[0]
      get_content_pane.set_layout nil
      lines.each_with_index{|line, idx|
        jlabel = JLabel.new line
        jlabel.set_bounds(10, 15*idx, 550, 24)
        get_content_pane.add jlabel
      }
      close = JButton.new( close_button_text ).on_clicked {
        self.dispose
      }
      number_of_lines = lines.length
      close.set_bounds(125,30+15*number_of_lines, close_button_text.length * 15,25)
      get_content_pane.add close
      set_size 550, 100+(15*number_of_lines) # XXX variable width? or use swing build in better?
      set_visible true
      setDefaultCloseOperation JFrame::DISPOSE_ON_CLOSE
      setLocationRelativeTo nil # center it on the screen
      
    end
    alias close dispose # yikes
  end


  class DropDownSelector < JDialog # JDialog is blocking...
    
    def initialize parent, options_array, prompt_for_top_entry
      super parent, true
      set_title prompt_for_top_entry
      @drop_down_elements = options_array
      @selected_idx = nil
      box = JComboBox.new
      box.add_action_listener do |e|
        idx = box.get_selected_index
        if idx != 0
          # don't count choosing the first as a real entry
          @selected_idx = box.get_selected_index - 1
          dispose
        end
      end

      box.add_item @prompt = prompt_for_top_entry # put something in index 0
      options_array.each{|drive|
        box.add_item drive
      }
      add box
      pack # how do you get this arbitrary size? what the...
      
    end
    
    # returns index from initial array that they selected, or raises if they hit the x on it
    def go_selected_index
      puts 'select from dropdown window'
      show # blocks...
      raise 'did not select, exited early ' + @prompt unless @selected_idx
      @selected_idx
    end
    
    def go_selected_value
      puts 'select from dropdown window ' + @drop_down_elements[-1] + ' ...'
      show # blocks...
      raise 'did not select, exited early ' + @prompt unless @selected_idx
      @drop_down_elements[@selected_idx]
    end
    
  end
  
end