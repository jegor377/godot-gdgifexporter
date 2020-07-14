# Licensed under the MIT License <http://opensource.org/licenses/MIT>.
# SPDX-License-Identifier: MIT
# Copyright 2020 Igor Santarek

# Permission is hereby granted, free of charge, to any  person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software  without restriction, including without limitation the rights
# to use, copy,   modify, merge,  publish, distribute,  sublicense, and/or sell
# copies  of  the Software,  and  to  permit persons  to  whom the Software  is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE  IS PROVIDED "AS IS", WITHOUT WARRANTY  OF  ANY KIND,  EXPRESS OR
# IMPLIED,  INCLUDING BUT  NOT  LIMITED TO  THE  WARRANTIES OF  MERCHANTABILITY,
# FITNESS FOR  A PARTICULAR PURPOSE AND  NONINFRINGEMENT. IN NO EVENT  SHALL THE
# AUTHORS  OR COPYRIGHT  HOLDERS  BE  LIABLE FOR  ANY  CLAIM,  DAMAGES OR  OTHER
# LIABILITY, WHETHER IN AN ACTION OF  CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE  OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

extends Node


class LSB_LZWBitPacker:
	var bit_index: int = 0
	var byte: int = 0

	var chunks: PoolByteArray = PoolByteArray([])

	func get_bit(value: int, index: int) -> int:
		return (value >> index) & 1

	func set_bit(value: int, index: int) -> int:
		return value | (1 << index)

	func put_byte():
		chunks.append(byte)
		bit_index = 0
		byte = 0

	func write_bits(value: int, bits_count: int) -> void:
		for i in range(bits_count):
			if self.get_bit(value, i) == 1:
				byte = self.set_bit(byte, bit_index)

			bit_index += 1
			if bit_index == 8:
				self.put_byte()

	func pack() -> PoolByteArray:
		if bit_index != 0:
			self.put_byte()
		return chunks

	func reset() -> void:
		bit_index = 0
		byte = 0
		chunks = PoolByteArray([])
