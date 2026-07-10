package object coupledL2 {
  import chisel3._

  // These opcodes are internal to CPL2 tasks when standard TileLink uses 3-bit opcodes.
  private[coupledL2] def CBOClean = 12.U(4.W)
  private[coupledL2] def CBOFlush = 13.U(4.W)
  private[coupledL2] def CBOInval = 14.U(4.W)
  private[coupledL2] def CBOAck = 8.U(4.W)
}
