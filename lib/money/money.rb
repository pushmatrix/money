require 'bigdecimal'
require 'bigdecimal/util'

class Money
  include Comparable
  
  attr_reader :value, :cents

  def initialize(value = 0)
    raise ArgumentError if value.respond_to?(:nan?) && value.nan?
    
    @value = value_to_decimal(value).round(2)
    @cents = (@value * 100).to_i
  end
  
  def <=>(other)
    cents <=> other.cents
  end
  
  def +(other)
    Money.new(value + other.to_money.value)
  end

  def -(other)
    Money.new(value - other.to_money.value)
  end
  
  def *(numeric)
    Money.new(value * numeric)
  end
  
  def /(numeric)
    raise "[Money] Dividing money objects can lose pennies. Use #split instead"
  end
    
  def inspect
    "#<#{self.class} value:#{self.to_s}>"
  end
  
  def ==(other)
    eql?(other)
  end
  
  def eql?(other)
    self.class == other.class && value == other.value
  end
  
  def hash
    value.hash
  end
  
  def self.parse(input)
    parser.parse(input)
  end
  
  # allow parser to be set via dependency injection.
  def self.parser
    @@parser ||= MoneyParser
  end
  
  def self.parser=(new_parser_class)
    @@parser = new_parser_class
  end
  
  def self.empty
    Money.new
  end
  
  def self.from_cents(cents)
    Money.new(cents.round.to_f / 100)
  end
  
  def to_money
    self
  end
  
  def zero?
    value.zero?
  end
  
  # dangerous, this *will* shave off all your cents
  def to_i
    value.to_i
  end
  
  def to_f
    value.to_f
  end
  
  def to_s
    sprintf("%.2f", value.to_f)
  end
  
  def to_liquid
    cents
  end

  def to_json(options = {})
    to_s
  end
  
  def as_json(*args)
    to_s
  end
  
  def abs
    Money.new(value.abs)
  end

  def fraction(rate)
    raise ArgumentError, "rate should be positive" if rate < 0

    result = value / (1 + rate)
    Money.new(result)
  end
  
  # Allocates money between different parties without losing pennies. 
  # After the mathmatically split has been performed, left over pennies will
  # be distributed round-robin amongst the parties. This means that parties
  # listed first will likely recieve more pennies then ones that are listed later
  # 
  # @param [0.50, 0.25, 0.25] to give 50% of the cash to party1, 25% ot party2, and 25% to party3.
  #
  # @return [Array<Money, Money, Money>]
  #
  # @example
  #   Money.new(5, "USD").allocate([0.3,0.7)) #=> [Money.new(2), Money.new(3)]  
  #   Money.new(100, "USD").allocate([0.33,0.33,0.33]) #=> [Money.new(34), Money.new(33), Money.new(33)]
  def allocate(splits)
    allocations = (splits.inject(BigDecimal.new("0")) {|sum, i| sum += i }).to_f
    raise ArgumentError, "splits add to more than 100%" if (allocations - 1.0) > Float::EPSILON

    left_over = cents
 
    amounts = splits.collect do |ratio|
      fraction = (cents * ratio / allocations).floor
      left_over -= fraction
      fraction
    end

    left_over.times { |i| amounts[i % amounts.length] += 1 }

    return amounts.collect { |cents| Money.from_cents(cents) }
  end

  # Split money amongst parties evenly without loosing pennies.
  #
  # @param [2] number of parties.
  #
  # @return [Array<Money, Money, Money>]
  #
  # @example
  #   Money.new(100, "USD").split(3) #=> [Money.new(34), Money.new(33), Money.new(33)]
  def split(num)
    raise ArgumentError, "need at least one party" if num < 1
    low = Money.from_cents(cents / num)
    high = Money.from_cents(low.cents + 1)

    remainder = cents % num
    result = []

    num.times do |index|
      result[index] = index < remainder ? high : low
    end

    return result
  end

  private
  # poached from Rails
  def value_to_decimal(value)
    # Using .class is faster than .is_a? and
    # subclasses of BigDecimal will be handled
    # in the else clause
    if value.class == BigDecimal
      value
    elsif value.respond_to?(:to_d)
      value.to_d
    else
      value.to_s.to_d
    end
  end
end

