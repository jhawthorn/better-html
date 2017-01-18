require 'html_tokenizer'
require 'action_view'

class BetterHtml::BetterErb
  class Implementation < ActionView::Template::Handlers::Erubis
    def initialize(*)
      @parser = HtmlTokenizer::Parser.new
      @newline_pending = 0
      @line_number = 1
      super
    end

    def add_preamble(src)
      src << "@output_buffer = (output_buffer.presence || ActionView::OutputBuffer.new);"
    end

    def add_text(src, text)
      return if text.empty?

      if text == "\n"
        @line_number += 1
        @newline_pending += 1
      else
        src << "@output_buffer.safe_append='"
        src << "\n" * @newline_pending if @newline_pending > 0
        src << escape_text(text)
        src << "'.freeze;"

        @parser.parse(text)

        @line_number += text.count("\n")
        @newline_pending = 0
      end
    end

    def add_expr_literal(src, code)
      add_expr_auto_escaped(src, code, true)
    end

    def add_expr_escaped(src, code)
      add_expr_auto_escaped(src, code, false)
    end

    def add_stmt(src, code)
      flush_newline_if_pending(src)

      @line_number += code.count("\n")
      block_check(src, code)
      super
    end

    private

    def class_name
      "BetterHtml::BetterErb::ValidatedOutputBuffer"
    end

    def wrap_method
      "#{class_name}.wrap"
    end

    def add_expr_auto_escaped(src, code, auto_escape)
      flush_newline_if_pending(src)

      @line_number += code.count("\n")

      src << "#{wrap_method}(@output_buffer, (#{parser_context.inspect}), '#{escape_text(code)}'.freeze, #{auto_escape})"
      method_name = "safe_#{@parser.context}_append"
      if code =~ BLOCK_EXPR
        block_check(src, code)
        src << ".#{method_name}= " << code
      else
        src << ".#{method_name}=(" << code << ");"
      end
    end

    def parser_context
      if [:quoted_value, :unquoted_value, :space_after_attribute].include?(@parser.context)
        {
          tag_name: @parser.tag_name,
          attribute_name: @parser.attribute_name,
          attribute_value: @parser.attribute_value,
          attribute_quoted: @parser.attribute_quoted?,
        }
      elsif [:attribute_name, :after_attribute_name, :after_equal].include?(@parser.context)
        {
          tag_name: @parser.tag_name,
          attribute_name: @parser.attribute_name,
        }
      elsif [:tag, :tag_name, :tag_end].include?(@parser.context)
        {
          tag_name: @parser.tag_name,
        }
      elsif @parser.context == :rawtext
        {
          tag_name: @parser.tag_name,
          rawtext_text: @parser.rawtext_text,
        }
      elsif @parser.context == :comment
        {
          comment_text: @parser.comment_text,
        }
      elsif [:none, :solidus_or_tag_name].include?(@parser.context)
        {}
      else
        raise RuntimeError, "Tried to interpolate into unknown location #{@parser.context}."
      end
    end

    def block_check(src, code)
      unless @parser.context == :none || @parser.context == :rawtext
        s = "Ruby statement not allowed.\n"
        s << "In '#{@parser.context}' on line #{@line_number}:\n"
        s << "  #{code.lines.join("\n  ")}"
        raise BetterHtml::DontInterpolateHere, s
      end
    end
  end
end
