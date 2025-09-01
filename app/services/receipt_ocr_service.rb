require 'httparty'
require 'base64'

class ReceiptOcrService
  include HTTParty
  
  base_uri 'https://api.ocr.space'
  
  # Free OCR.Space API key - using the demo key for testing
  # Get your own free key at https://ocr.space/ocrapi
  API_KEY = ENV['OCR_SPACE_API_KEY'] || 'helloworld'
  
  def self.extract_text_from_image(image_file)
    Rails.logger.info "Starting OCR processing for image"
    
    # Convert image to base64
    image_file.rewind if image_file.respond_to?(:rewind)
    image_base64 = Base64.encode64(image_file.read)
    
    Rails.logger.info "Image converted to base64, size: #{image_base64.length}"
    
    options = {
      body: {
        base64Image: "data:image/jpeg;base64,#{image_base64}",
        apikey: API_KEY,
        language: 'ger',
        isOverlayRequired: false,
        OCREngine: 2,
        scale: true,
        isTable: false
      }
    }
    
    Rails.logger.info "Sending request to OCR.Space API"
    response = post('/parse/image', options)
    
    Rails.logger.info "OCR API Response: #{response.code}, Body: #{response.body}"
    
    if response.success? && response.parsed_response['OCRExitCode'] == 1
      {
        success: true,
        text: response.parsed_response['ParsedResults']&.first&.[]('ParsedText') || '',
        confidence: extract_confidence(response.parsed_response)
      }
    else
      error_msg = response.parsed_response['ErrorMessage'] || 'OCR processing failed'
      Rails.logger.error "OCR failed: #{error_msg}"
      
      # Return mock data for development/testing when OCR fails
      if Rails.env.development?
        Rails.logger.info "Returning mock OCR data for development"
        {
          success: true,
          text: "ALDI\nFilialnummer 1234\nMusterstraße 123\n12345 Berlin\n\nBananen        2,49 €\nVollkornbrot   1,29 €\nMilch 3,5%     0,89 €\n\nZwischensumme  4,67 €\nMwSt 7%        0,33 €\nSumme          5,00 €\n\n01.09.2025 14:23\nVielen Dank!",
          confidence: 0.75
        }
      else
        {
          success: false,
          error: error_msg,
          confidence: 0
        }
      end
    end
  rescue => e
    Rails.logger.error "OCR exception: #{e.message}"
    
    # Return mock data for development when there's an exception
    if Rails.env.development?
      Rails.logger.info "Returning mock OCR data due to exception"
      {
        success: true,
        text: "REWE\nRewe Markt GmbH\nKaiserstraße 45\n50321 Brühl\n\nÄpfel Bio       3,49 €\nNudeln 500g     1,19 €\nTomatensoße     0,89 €\nKäse Gouda      2,99 €\n\nZwischensumme   8,56 €\nMwSt 7%         0,60 €\nGesamtbetrag    9,16 €\n\n01.09.2025 16:45\nVielen Dank für Ihren Einkauf!",
        confidence: 0.8
      }
    else
      {
        success: false,
        error: e.message,
        confidence: 0
      }
    end
  end
  
  def self.parse_receipt_data(text)
    return nil if text.blank?
    
    lines = text.split(/\r?\n/).map(&:strip).reject(&:blank?)
    
    Rails.logger.info "Parsing receipt with #{lines.length} lines"
    Rails.logger.debug "Receipt lines: #{lines.inspect}"
    
    # Extract merchant name (usually first or second line)
    merchant = find_merchant(lines)
    Rails.logger.info "Found merchant: #{merchant}"
    
    # Extract total amount
    total = find_total(lines)
    Rails.logger.info "Found total: #{total}"
    
    # Extract date
    date = find_date(lines)
    Rails.logger.info "Found date: #{date}"
    
    # Extract items
    items = find_items(lines)
    Rails.logger.info "Found #{items.length} items"
    
    {
      merchant: merchant,
      total: total,
      date: date,
      items: items,
      raw_text: text
    }
  end
  
  private
  
  def self.extract_confidence(response)
    # OCR.Space doesn't provide confidence directly, estimate based on response
    if response['ParsedResults']&.first&.[]('ParsedText')&.present?
      0.8 # Default confidence for successful parsing
    else
      0.0
    end
  end
  
  def self.find_merchant(lines)
    # Look for merchant name in first few lines, excluding common receipt headers
    exclude_patterns = /^(receipt|invoice|bill|thank you|welcome|hier bin ich mensch|hier kauf ich ein)/i
    
    lines.first(5).each do |line|
      next if line.match?(exclude_patterns)
      next if line.match?(/^\d+/) # Skip lines starting with numbers
      next if line.length < 2 # Skip very short lines
      
      # Prioritize known German store names
      return line if line.match?(/^(dm|aldi|rewe|edeka|lidl|kaufland|netto|penny)$/i)
      
      # Accept lines with letters, spaces, ampersand, and some German characters
      return line if line.match?(/^[a-zA-ZäöüÄÖÜß\s&\-]+$/) && line.length >= 2
    end
    
    'Unknown Merchant'
  end
  
  def self.find_total(lines)
    Rails.logger.info "Finding total in lines: #{lines.inspect}"
    
    # Look for total patterns (German and English)
    total_patterns = [
      # German patterns - more specific first
      /zu\s+zahlen[:\s]*(\d+,\d{2})\s*€/i,
      /summe[:\s]*(\d+,\d{2})\s*€/i,
      /gesamtbetrag[:\s]*(\d+,\d{2})\s*€/i,
      /gesamt[:\s]*(\d+,\d{2})\s*€/i,
      # Pattern to match cases where "ZU ZAHLEN" is on one line and amount on next
      /zu\s+zahlen/i,
      # Generic Euro patterns
      /(\d+,\d{2})\s*€\s*$/,
      # English patterns  
      /total[:\s]*\$?(\d+\.\d{2})/i,
      /amount[:\s]*\$?(\d+\.\d{2})/i,
      /^total[:\s]*(\d+\.\d{2})/i,
      /\$(\d+\.\d{2})$/,
      /(\d+\.\d{2})\s*$/ # Last resort: any amount at end of line
    ]
    
    # First, check for German total patterns
    # Check for "ZU ZAHLEN" (ALDI style)
    zu_zahlen_index = lines.find_index { |l| l.match?(/zu\s+zahlen/i) }
    if zu_zahlen_index
      Rails.logger.info "Found ZU ZAHLEN at index: #{zu_zahlen_index}, processing..."
      
      # Look in lines after "ZU ZAHLEN" for Euro amounts
      lines_after_zu_zahlen = lines[zu_zahlen_index..-1]
      Rails.logger.info "Lines after ZU ZAHLEN: #{lines_after_zu_zahlen.inspect}"
      
      euro_amounts = []
      
      lines_after_zu_zahlen.each do |search_line|
        # Look for amounts with € symbol
        search_line.scan(/(\d+,\d{2})\s*€/) do |amount_match|
          amount = amount_match[0].gsub(',', '.').to_f
          Rails.logger.info "Found Euro amount: #{amount}"
          euro_amounts << amount if amount > 0 && amount < 10000
        end
        
        # Look for standalone amounts like "23,42" (likely the final total)
        if search_line.strip.match(/^(\d+,\d{2})$/)
          amount = search_line.strip.gsub(',', '.').to_f
          Rails.logger.info "Found standalone amount: #{amount}"
          euro_amounts << amount if amount > 0 && amount < 10000
        end
      end
      
      Rails.logger.info "All amounts found after ZU ZAHLEN: #{euro_amounts.inspect}"
      
      # Return the largest amount found (should be the total)
      if euro_amounts.any?
        max_amount = euro_amounts.max
        Rails.logger.info "Returning max amount from ZU ZAHLEN section: #{max_amount}"
        return max_amount
      end
    end
    
    # Check for "SUMME EUR" pattern (DM, other German stores)
    summe_index = lines.find_index { |l| l.match?(/summe\s+eur/i) }
    if summe_index
      Rails.logger.info "Found SUMME EUR at index: #{summe_index}, processing..."
      
      # Look for amounts after SUMME EUR - DM receipts have individual prices followed by total
      lines_after_summe = lines[summe_index..summe_index+15] || []
      Rails.logger.info "Lines after SUMME EUR: #{lines_after_summe.inspect}"
      
      summe_amounts = []
      
      lines_after_summe.each do |search_line|
        # Look for Euro amounts in same line as SUMME EUR
        if search_line.match?(/summe\s+eur/i) && (amount_match = search_line.match(/(\d+,\d{2})/))
          amount = amount_match[1].gsub(',', '.').to_f
          Rails.logger.info "Found amount on SUMME EUR line: #{amount}"
          summe_amounts << amount if amount > 0 && amount < 10000
        end
        
        # Look for standalone amounts after SUMME EUR (skip negative amounts like "- 16,85")
        if search_line.strip.match?(/^(\d+,\d{2})$/)
          amount = search_line.strip.gsub(',', '.').to_f
          Rails.logger.info "Found standalone amount after SUMME EUR: #{amount}"
          summe_amounts << amount if amount > 0 && amount < 10000
        end
      end
      
      Rails.logger.info "All amounts found after SUMME EUR: #{summe_amounts.inspect}"
      
      # Return the largest amount (should be the total, not individual item prices)
      if summe_amounts.any?
        max_amount = summe_amounts.max
        Rails.logger.info "Returning max amount from SUMME EUR section: #{max_amount}"
        return max_amount
      end
    end
    
    # Fallback to regular pattern matching if German patterns didn't work
    Rails.logger.info "ZU ZAHLEN method didn't find amount, falling back to regular patterns"
    
    # Check lines in reverse order (totals usually at bottom)
    lines.reverse.each_with_index do |line, index|
      total_patterns.each do |pattern|
        if match = line.match(pattern)
          # If we have a capture group (amount), use it
          if match[1]
            amount_str = match[1]
            # Convert German decimal format (comma) to English (dot)
            amount = amount_str.gsub(',', '.').to_f
            Rails.logger.info "Found amount with pattern #{pattern}: #{amount}"
            return amount if amount > 0 && amount < 10000 # Reasonable range
          elsif pattern.source.include?('zu.*zahlen') # Special case for "ZU ZAHLEN"
            Rails.logger.info "Found ZU ZAHLEN pattern, looking for amount..."
            # For ALDI receipts, look for the last Euro amount after finding "ZU ZAHLEN"
            zu_zahlen_index = lines.find_index { |l| l.match?(/zu\s+zahlen/i) }
            Rails.logger.info "ZU ZAHLEN found at index: #{zu_zahlen_index}"
            
            if zu_zahlen_index
              # Look in lines after "ZU ZAHLEN" for Euro amounts
              lines_after_zu_zahlen = lines[zu_zahlen_index..-1]
              Rails.logger.info "Lines after ZU ZAHLEN: #{lines_after_zu_zahlen.inspect}"
              
              euro_amounts = []
              
              lines_after_zu_zahlen.each do |search_line|
                # Look for amounts with € symbol
                search_line.scan(/(\d+,\d{2})\s*€/) do |amount_match|
                  amount = amount_match[0].gsub(',', '.').to_f
                  Rails.logger.info "Found Euro amount: #{amount}"
                  euro_amounts << amount if amount > 0 && amount < 10000
                end
                
                # Look for standalone amounts like "23,42" (likely the final total)
                if search_line.strip.match(/^(\d+,\d{2})$/)
                  amount = search_line.strip.gsub(',', '.').to_f
                  Rails.logger.info "Found standalone amount: #{amount}"
                  euro_amounts << amount if amount > 0 && amount < 10000
                end
              end
              
              Rails.logger.info "All amounts found: #{euro_amounts.inspect}"
              
              # Return the largest amount found (should be the total)
              if euro_amounts.any?
                max_amount = euro_amounts.max
                Rails.logger.info "Returning max amount: #{max_amount}"
                return max_amount
              end
            end
          end
        end
      end
    end
    
    0.0
  end
  
  def self.find_date(lines)
    date_patterns = [
      # German formats (DD.MM.YYYY)
      /(\d{1,2}\.\d{1,2}\.\d{2,4})/,
      # English formats
      /(\d{1,2}\/\d{1,2}\/\d{2,4})/,
      /(\d{1,2}-\d{1,2}-\d{2,4})/,
      /(\d{4}-\d{1,2}-\d{1,2})/
    ]
    
    lines.each do |line|
      date_patterns.each do |pattern|
        if match = line.match(pattern)
          begin
            return Date.parse(match[1])
          rescue Date::Error
            next
          end
        end
      end
    end
    
    Date.current
  end
  
  def self.find_items(lines)
    items = []
    
    lines.each do |line|
      # Look for lines with item and price pattern
      if match = line.match(/^(.+?)\s+\$?(\d+\.\d{2})$/)
        item_name = match[1].strip
        price = match[2].to_f
        
        # Skip if it looks like a total line
        next if item_name.match?(/total|subtotal|tax|amount/i)
        next if item_name.length < 2
        
        items << {
          name: item_name,
          price: price
        }
      end
    end
    
    items
  end
end