const VERSION = 6
const SIZE = VERSION * 4 + 17
const DATA_CODEWORDS = 136
const BLOCK_DATA_CODEWORDS = 68
const ECC_CODEWORDS = 18
const MASK = 0
const MAX_BYTE_LENGTH = 134

export function createQrSvg(text: string) {
  const bytes = Array.from(new TextEncoder().encode(text))
  if (bytes.length > MAX_BYTE_LENGTH) {
    throw new Error('QR payload is too long')
  }

  const modules = Array.from({ length: SIZE }, () => Array<boolean>(SIZE).fill(false))
  const reserved = Array.from({ length: SIZE }, () => Array<boolean>(SIZE).fill(false))

  const set = (x: number, y: number, dark: boolean, reserve = true) => {
    if (x < 0 || y < 0 || x >= SIZE || y >= SIZE) return
    modules[y][x] = dark
    if (reserve) reserved[y][x] = true
  }

  drawFinder(set, 0, 0)
  drawFinder(set, SIZE - 7, 0)
  drawFinder(set, 0, SIZE - 7)
  drawAlignment(set, 34, 34)
  drawTiming(set)
  reserveFormatAreas(reserved)

  const dataCodewords = createDataCodewords(bytes)
  const codewords = interleaveBlocks(dataCodewords)
  placeCodewords(modules, reserved, codewords)
  applyMask(modules, reserved)
  drawFormatBits(set)

  return renderSvg(modules)
}

function drawFinder(set: (x: number, y: number, dark: boolean, reserve?: boolean) => void, left: number, top: number) {
  for (let y = -1; y <= 7; y++) {
    for (let x = -1; x <= 7; x++) {
      const xx = left + x
      const yy = top + y
      const inPattern = x >= 0 && x <= 6 && y >= 0 && y <= 6
      const dark =
        inPattern &&
        (x === 0 || x === 6 || y === 0 || y === 6 || (x >= 2 && x <= 4 && y >= 2 && y <= 4))
      set(xx, yy, dark)
    }
  }
}

function drawAlignment(set: (x: number, y: number, dark: boolean, reserve?: boolean) => void, centerX: number, centerY: number) {
  for (let y = -2; y <= 2; y++) {
    for (let x = -2; x <= 2; x++) {
      const dark = Math.max(Math.abs(x), Math.abs(y)) === 2 || (x === 0 && y === 0)
      set(centerX + x, centerY + y, dark)
    }
  }
}

function drawTiming(set: (x: number, y: number, dark: boolean, reserve?: boolean) => void) {
  for (let i = 8; i < SIZE - 8; i++) {
    const dark = i % 2 === 0
    set(6, i, dark)
    set(i, 6, dark)
  }
}

function reserveFormatAreas(reserved: boolean[][]) {
  const reserve = (x: number, y: number) => {
    if (x >= 0 && y >= 0 && x < SIZE && y < SIZE) reserved[y][x] = true
  }

  for (let i = 0; i <= 5; i++) {
    reserve(8, i)
    reserve(i, 8)
  }
  reserve(8, 7)
  reserve(8, 8)
  reserve(7, 8)

  for (let i = 0; i < 8; i++) reserve(SIZE - 1 - i, 8)
  for (let i = 8; i < 15; i++) reserve(8, SIZE - 15 + i)
  reserve(8, SIZE - 8)
}

function createDataCodewords(bytes: number[]) {
  const bits: number[] = []
  appendBits(bits, 0b0100, 4)
  appendBits(bits, bytes.length, 8)
  for (const value of bytes) appendBits(bits, value, 8)

  const capacityBits = DATA_CODEWORDS * 8
  appendBits(bits, 0, Math.min(4, capacityBits - bits.length))
  while (bits.length % 8 !== 0) bits.push(0)

  const codewords: number[] = []
  for (let i = 0; i < bits.length; i += 8) {
    let value = 0
    for (let j = 0; j < 8; j++) value = (value << 1) | bits[i + j]
    codewords.push(value)
  }

  for (let pad = 0xec; codewords.length < DATA_CODEWORDS; pad = pad === 0xec ? 0x11 : 0xec) {
    codewords.push(pad)
  }
  return codewords
}

function appendBits(bits: number[], value: number, length: number) {
  for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1)
}

function interleaveBlocks(dataCodewords: number[]) {
  const blocks = [
    dataCodewords.slice(0, BLOCK_DATA_CODEWORDS),
    dataCodewords.slice(BLOCK_DATA_CODEWORDS, BLOCK_DATA_CODEWORDS * 2)
  ]
  const eccBlocks = blocks.map((block) => reedSolomonRemainder(block, ECC_CODEWORDS))
  const result: number[] = []

  for (let i = 0; i < BLOCK_DATA_CODEWORDS; i++) {
    for (const block of blocks) result.push(block[i])
  }
  for (let i = 0; i < ECC_CODEWORDS; i++) {
    for (const block of eccBlocks) result.push(block[i])
  }
  return result
}

function reedSolomonRemainder(data: number[], degree: number) {
  const divisor = reedSolomonDivisor(degree)
  const result = Array<number>(degree).fill(0)

  for (const value of data) {
    const factor = value ^ result.shift()!
    result.push(0)
    for (let i = 0; i < divisor.length; i++) {
      result[i] ^= gfMultiply(divisor[i], factor)
    }
  }
  return result
}

function reedSolomonDivisor(degree: number) {
  const result = Array<number>(degree - 1).fill(0)
  result.push(1)

  let root = 1
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < result.length; j++) {
      result[j] = gfMultiply(result[j], root)
      if (j + 1 < result.length) result[j] ^= result[j + 1]
    }
    root = gfMultiply(root, 0x02)
  }
  return result
}

function gfMultiply(left: number, right: number) {
  let result = 0
  let value = left
  let factor = right

  while (factor > 0) {
    if ((factor & 1) !== 0) result ^= value
    factor >>>= 1
    value <<= 1
    if ((value & 0x100) !== 0) value ^= 0x11d
  }
  return result & 0xff
}

function placeCodewords(modules: boolean[][], reserved: boolean[][], codewords: number[]) {
  const bits = codewords.flatMap((value) => {
    const result: number[] = []
    appendBits(result, value, 8)
    return result
  })

  let bitIndex = 0
  let upward = true
  for (let right = SIZE - 1; right >= 1; right -= 2) {
    if (right === 6) right--
    for (let vert = 0; vert < SIZE; vert++) {
      const y = upward ? SIZE - 1 - vert : vert
      for (let offset = 0; offset < 2; offset++) {
        const x = right - offset
        if (!reserved[y][x]) {
          modules[y][x] = bitIndex < bits.length ? bits[bitIndex] === 1 : false
          bitIndex++
        }
      }
    }
    upward = !upward
  }
}

function applyMask(modules: boolean[][], reserved: boolean[][]) {
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      if (!reserved[y][x] && (x + y) % 2 === MASK) {
        modules[y][x] = !modules[y][x]
      }
    }
  }
}

function drawFormatBits(set: (x: number, y: number, dark: boolean, reserve?: boolean) => void) {
  const bits = formatBits(MASK)
  for (let i = 0; i <= 5; i++) set(8, i, getBit(bits, i))
  set(8, 7, getBit(bits, 6))
  set(8, 8, getBit(bits, 7))
  set(7, 8, getBit(bits, 8))
  for (let i = 9; i < 15; i++) set(14 - i, 8, getBit(bits, i))

  for (let i = 0; i < 8; i++) set(SIZE - 1 - i, 8, getBit(bits, i))
  for (let i = 8; i < 15; i++) set(8, SIZE - 15 + i, getBit(bits, i))
  set(8, SIZE - 8, true)
}

function formatBits(mask: number) {
  const data = (0b01 << 3) | mask
  let remainder = data
  for (let i = 0; i < 10; i++) {
    remainder = (remainder << 1) ^ (((remainder >>> 9) & 1) === 0 ? 0 : 0x537)
  }
  return ((data << 10) | remainder) ^ 0x5412
}

function getBit(value: number, index: number) {
  return ((value >>> index) & 1) !== 0
}

function renderSvg(modules: boolean[][]) {
  const quiet = 4
  const viewSize = SIZE + quiet * 2
  const commands: string[] = []

  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      if (modules[y][x]) commands.push(`M${x + quiet} ${y + quiet}h1v1h-1z`)
    }
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${viewSize} ${viewSize}" role="img" aria-label="TOTP QR code"><rect width="${viewSize}" height="${viewSize}" fill="#fff"/><path d="${commands.join('')}" fill="#172033"/></svg>`
}
