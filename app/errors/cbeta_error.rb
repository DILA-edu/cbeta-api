class CbetaError < StandardError
  attr :code
  def initialize(code)
    super()
    @code = code
  end
end