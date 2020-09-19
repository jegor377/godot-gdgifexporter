extends Reference


func int_to_word(value: int) -> PoolByteArray:
	return PoolByteArray([value & 255, (value >> 8) & 255])

func word_to_int(value: PoolByteArray) -> int:
	return (value[1] << 8) | value[0]
