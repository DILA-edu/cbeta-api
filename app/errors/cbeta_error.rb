class CbetaError < StandardError
  attr :code
  def initialize(code)
    @code = code
  end
end