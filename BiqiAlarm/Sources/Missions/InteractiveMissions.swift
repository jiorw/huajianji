import Foundation
import SwiftUI

// MARK: - 四个「动脑」使命：数学题 / 记忆翻牌 / 找不同符号 / 点击挑战
//
// 契约同 MissionHost：每个视图只有 config + done 两个存储属性，全部靠成员初始化器创建，
// 完成任务时调用 done()。随机内容一律在 .task / 按钮动作里生成，绝不在 body 里摇骰子。

// MARK: - 共用零件（只在本文件内可见，避免和别的使命文件撞名）

/// 一行状态条：左边说明，右边玻璃小牌
private struct MissionStrip: View {
    let text: String
    var systemImage: String
    var badge: String?
    var badgeTint: Color?

    var body: some View {
        HStack(spacing: 10) {
            MissionHint(text: text, systemImage: systemImage)
            Spacer(minLength: 8)
            if let badge {
                Text(badge).glassChip(tint: badgeTint)
            }
        }
    }
}

/// 通用玻璃方块按钮：靠 background 上色，方便做对/错的反馈色。
/// 注意成员顺序：带默认值的一律排在 action 前面，成员初始化器要求实参按声明顺序传。
private struct MissionTileButton<Label: View>: View {
    var fill: Color = Color.white.opacity(0.12)
    var stroke: Color = Color.white.opacity(0.32)
    var lineWidth: CGFloat = 1
    var isDisabled: Bool = false
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, minHeight: 58)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(stroke, lineWidth: lineWidth)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private func clamped(_ value: Int, _ low: Int, _ high: Int) -> Int {
    min(max(value, low), high)
}

// MARK: - 1. 数学题

private enum MathOp: String, CaseIterable {
    case add = "+"
    case sub = "−"
    case mul = "×"
    case div = "÷"

    var sign: String { rawValue }
}

private enum MathForm: Int, CaseIterable {
    case choice        // 四选一
    case fillOperator  // 运算符填空
    case typed         // 数字键盘输入
}

private struct MathQuestion: Identifiable {
    let id = UUID()
    let left: Int
    let right: Int
    let op: MathOp
    let answer: Int
    let form: MathForm
    let options: [Int]
}

private enum MathLab {
    /// 难度 1...5 → 操作数位数 1 / 2 / 2 / 3 / 4
    static func digits(for difficulty: Int) -> Int {
        [1, 2, 2, 3, 4][clamped(difficulty, 1, 5) - 1]
    }

    static func span(_ digits: Int) -> ClosedRange<Int> {
        switch digits {
        case 1: return 2...9
        case 2: return 12...99
        case 3: return 120...999
        default: return 1200...9999
        }
    }

    /// 减法要求不为负、除法只在整除时有值，返回 nil 表示这个式子不成立
    static func value(_ a: Int, _ b: Int, _ op: MathOp) -> Int? {
        switch op {
        case .add: return a + b
        case .sub: return a >= b ? a - b : nil
        case .mul: return a * b
        case .div: return b > 0 && a % b == 0 ? a / b : nil
        }
    }

    static func makeSet(count: Int, difficulty: Int) -> [MathQuestion] {
        (0..<max(1, count)).map { _ in make(difficulty: difficulty) }
    }

    static func make(difficulty: Int) -> MathQuestion {
        let d = digits(for: difficulty)
        let op = MathOp.allCases.randomElement() ?? .add
        var left = Int.random(in: span(d))
        var right = Int.random(in: span(min(2, d)))

        switch op {
        case .add:
            break
        case .sub:
            if right > left { swap(&left, &right) }
        case .mul:
            left = Int.random(in: span(min(2, d)))
            right = Int.random(in: 2...9)
        case .div:
            // 先定除数和商，再回推被除数，保证整除且结果非负
            right = Int.random(in: 2...9)
            left = right * Int.random(in: span(min(2, d)))
        }

        let answer = value(left, right, op) ?? 0
        var form = MathForm.allCases.randomElement() ?? .choice

        // 运算符填空要求答案唯一，否则退回四选一，绝不给用户留歧义题
        if form == .fillOperator {
            let hits = MathOp.allCases.filter { value(left, right, $0) == answer }
            if hits.count != 1 { form = .choice }
        }

        let options: [Int]
        if form == .choice {
            options = choices(for: answer)
        } else {
            options = []
        }
        return MathQuestion(left: left, right: right, op: op, answer: answer,
                            form: form, options: options)
    }

    /// 三个干扰项：只在加减法附近做文章，乘除的干扰另走一套，避免一眼看出个位规律
    static func choices(for answer: Int) -> [Int] {
        let near = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 9, -9]
        let wide = [10, -10, 11, -11, 20, -20, 100, -100]
        var pool: [Int] = []
        for offset in (near + wide).shuffled() {
            let candidate = answer + offset
            if candidate >= 0, candidate != answer, !pool.contains(candidate) {
                pool.append(candidate)
            }
            if pool.count == 3 { break }
        }
        var pad = 1
        while pool.count < 3 {
            pool.append(answer + 1000 * pad)
            pad += 1
        }
        return (pool + [answer]).shuffled()
    }
}

struct MathMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var questions: [MathQuestion] = []
    @State private var index = 0
    @State private var round = 1
    @State private var typed = ""
    @State private var pickedNumber: Int?
    @State private var pickedOperator: MathOp?
    @State private var feedback: Feedback = .idle
    @State private var streak = 0
    @State private var wrongTotal = 0

    private enum Feedback: Int, Equatable {
        case idle, right, wrong
    }

    private var questionsPerRound: Int { max(1, config.targetCount) }
    private var totalRounds: Int { max(1, config.rounds) }
    private var current: MathQuestion? { questions.indices.contains(index) ? questions[index] : nil }

    var body: some View {
        VStack(spacing: 14) {
            topBar
            questionCard
            answerArea
                .disabled(feedback != .idle)
            Spacer(minLength: 0)
            footer
        }
        .task {
            if questions.isEmpty {
                questions = MathLab.makeSet(count: questionsPerRound, difficulty: config.difficulty)
            }
        }
    }

    private var topBar: some View {
        MissionStrip(text: "算对 \(questionsPerRound) 题过一轮",
                     systemImage: "function",
                     badge: totalRounds > 1 ? "第 \(clamped(round, 1, totalRounds))/\(totalRounds) 轮" : nil,
                     badgeTint: Palette.cool.opacity(0.45))
    }

    private var questionCard: some View {
        VStack(spacing: 10) {
            Text("第 \(min(index + 1, questionsPerRound))/\(questionsPerRound) 题 · \(MissionConfig.difficultyName(config.difficulty))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            if let question = current {
                Text(prompt(for: question))
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Text(capacity(for: question))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            } else {
                Text("正在出题…")
                    .font(.title3.weight(.semibold))
            }
            banner
        }
        .glassPanel(tint: cardTint)
        .scaleEffect(feedback == .right ? 1.015 : 1)
        .animation(.spring(duration: 0.3), value: feedback)
    }

    private var cardTint: Color? {
        switch feedback {
        case .idle: return nil
        case .right: return Color.green.opacity(0.26)
        case .wrong: return Color.red.opacity(0.30)
        }
    }

    @ViewBuilder
    private var banner: some View {
        switch feedback {
        case .idle:
            if wrongTotal > 0 {
                Text("答错 \(wrongTotal) 次，错了会换新题").font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
        case .right:
            Label("答对了，下一题", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
        case .wrong:
            Label("这题算错了，重新出一道", systemImage: "xmark.octagon.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var answerArea: some View {
        if let question = current {
            switch question.form {
            case .choice:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(question.options, id: \.self) { option in
                        MissionTileButton(fill: numberFill(option),
                                          isDisabled: feedback != .idle,
                                          action: { choose(option) }) {
                            Text("\(option)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                    }
                }
            case .fillOperator:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(MathOp.allCases, id: \.rawValue) { op in
                        MissionTileButton(fill: operatorFill(op),
                                          isDisabled: feedback != .idle,
                                          action: { choose(op) }) {
                            Text(op.sign)
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                }
            case .typed:
                typedPad
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if streak >= 2 {
                Text("连对 \(streak) 题").glassChip(tint: Palette.accent.opacity(0.5))
            }
            ProgressView(value: Double(min(index, questionsPerRound)),
                         total: Double(questionsPerRound))
                .tint(Palette.accent)
            MissionBigButton(title: "换一套题", systemImage: "arrow.clockwise",
                             action: { rebuild() })
        }
    }

    // MARK: 数字键盘

    private var typedPad: some View {
        VStack(spacing: 10) {
            Text(typed.isEmpty ? "按下方的数字键输入答案" : typed)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, minHeight: 52)
                .glassPanel(tint: Color.white.opacity(0.08))
            VStack(spacing: 8) {
                ForEach(MathMissionView.keypadRows.indices, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(MathMissionView.keypadRows[row], id: \.self) { key in
                            MissionTileButton(fill: Color.white.opacity(0.13),
                                              isDisabled: feedback != .idle,
                                              action: { tap(key) }) {
                                keyView(key)
                            }
                        }
                    }
                }
            }
            MissionBigButton(title: "确定", systemImage: "checkmark", prominent: true,
                             action: { submitTyped() })
        }
    }

    @ViewBuilder
    private func keyView(_ key: String) -> some View {
        if key == "del" {
            Image(systemName: "delete.left")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
        } else if key == "clr" {
            Text("清空")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        } else {
            Text(key)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private static let keypadRows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["clr", "0", "del"]
    ]

    private func tap(_ key: String) {
        guard feedback == .idle else { return }
        if key == "del" {
            var buffer = typed
            if !buffer.isEmpty { buffer.removeLast() }
            typed = buffer
        } else if key == "clr" {
            typed = ""
        } else if typed.count < 8 {
            typed = typed + key
        }
    }

    // MARK: 反馈配色

    private func prompt(for question: MathQuestion) -> String {
        switch question.form {
        case .choice:
            return "\(question.left) \(question.op.sign) \(question.right) = ?"
        case .fillOperator:
            return "\(question.left) ○ \(question.right) = \(question.answer)"
        case .typed:
            return "\(question.left) \(question.op.sign) \(question.right) = ?"
        }
    }

    private func capacity(for question: MathQuestion) -> String {
        switch question.form {
        case .choice: return "四选一，点你算出来的那个数"
        case .fillOperator: return "选一个运算符号，让等式成立"
        case .typed: return "用数字键盘输入答案"
        }
    }

    private func numberFill(_ option: Int) -> Color {
        guard feedback != .idle, let question = current else { return Color.white.opacity(0.13) }
        if option == question.answer { return Color.green.opacity(0.55) }
        if option == pickedNumber, feedback == .wrong { return Color.red.opacity(0.62) }
        return Color.white.opacity(0.13)
    }

    private func operatorFill(_ op: MathOp) -> Color {
        guard feedback != .idle, let question = current else { return Color.white.opacity(0.13) }
        if op == question.op { return Color.green.opacity(0.55) }
        if op == pickedOperator, feedback == .wrong { return Color.red.opacity(0.62) }
        return Color.white.opacity(0.13)
    }

    // MARK: 答题流程

    private func choose(_ option: Int) {
        guard feedback == .idle, let question = current, question.form == .choice else { return }
        pickedNumber = option
        settle(correct: option == question.answer)
    }

    private func choose(_ op: MathOp) {
        guard feedback == .idle, let question = current, question.form == .fillOperator else { return }
        pickedOperator = op
        settle(correct: op == question.op)
    }

    private func submitTyped() {
        guard feedback == .idle, let question = current, question.form == .typed else { return }
        let parsed = Int(typed) ?? -1
        settle(correct: parsed == question.answer)
    }

    private func settle(correct: Bool) {
        if correct {
            feedback = .right
            streak += 1
            Task {
                try? await Task.sleep(for: .seconds(0.55))
                advance()
            }
        } else {
            feedback = .wrong
            streak = 0
            wrongTotal += 1
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                replaceCurrent()
            }
        }
    }

    private func advance() {
        pickedNumber = nil
        pickedOperator = nil
        typed = ""
        feedback = .idle
        let next = index + 1
        if next >= questions.count {
            if round >= totalRounds {
                done()
                return
            }
            round += 1
            index = 0
            questions = MathLab.makeSet(count: questionsPerRound, difficulty: config.difficulty)
        } else {
            index = next
        }
    }

    private func replaceCurrent() {
        pickedNumber = nil
        pickedOperator = nil
        typed = ""
        feedback = .idle
        guard questions.indices.contains(index) else { return }
        var deck = questions
        deck[index] = MathLab.make(difficulty: config.difficulty)
        questions = deck
    }

    private func rebuild() {
        questions = MathLab.makeSet(count: questionsPerRound, difficulty: config.difficulty)
        index = 0
        typed = ""
        pickedNumber = nil
        pickedOperator = nil
        feedback = .idle
        streak = 0
    }
}

// MARK: - 2. 记忆翻牌

private struct MemoryTile: Identifiable {
    let id = UUID()
    let symbol: String
    var faceUp = false
    var matched = false
}

private enum MemoryArt {
    static let symbols: [String] = [
        "star.fill", "heart.fill", "moon.fill", "sun.max.fill", "cloud.rain.fill",
        "leaf.fill", "flame.fill", "drop.fill", "bell.fill", "bolt.fill",
        "gift.fill", "key.fill", "lock.fill", "flag.fill", "paperplane.fill",
        "pawprint.fill", "fish.fill", "bird.fill", "tortoise.fill", "car.fill",
        "house.fill", "tree.fill", "camera.fill", "music.note", "gamecontroller.fill",
        "airplane", "cup.and.saucer.fill", "fork.knife"
    ]
}

struct MemoryMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var tiles: [MemoryTile] = []
    @State private var pending: [Int] = []
    @State private var round = 1
    @State private var pairsDone = 0
    @State private var pairsTotal = 1
    @State private var misses = 0
    @State private var locked = false

    private var columns: Int { max(2, config.memoryCols) }
    private var cellCount: Int { max(4, config.memoryRows * config.memoryCols) }
    private var pairCount: Int { max(1, cellCount / 2) }
    private var totalRounds: Int { max(1, config.rounds) }
    private var cleared: Bool { pairsDone >= pairsTotal }

    var body: some View {
        VStack(spacing: 14) {
            MissionStrip(text: "翻开两张一样的就消掉",
                         systemImage: "rectangle.grid.3x3.fill",
                         badge: totalRounds > 1 ? "第 \(clamped(round, 1, totalRounds))/\(totalRounds) 轮" : nil,
                         badgeTint: Palette.cool.opacity(0.45))
            HStack(spacing: 10) {
                Text("\(config.memoryRows)×\(config.memoryCols) 格 · \(cellCount) 张").glassChip()
                Text("已消 \(pairsDone)/\(pairsTotal) 对").glassChip(tint: Palette.cool.opacity(0.4))
                Text("翻错 \(misses)").glassChip(tint: Color.red.opacity(0.4))
                Spacer()
            }
            board
            Spacer(minLength: 0)
            if cleared {
                Label("这一轮翻完了", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
            } else {
                MissionHint(text: "记住位置，翻错会盖回去", systemImage: "lightbulb")
            }
        }
        .task {
            if tiles.isEmpty { startRound(1) }
        }
    }

    private var board: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns),
                  spacing: 10) {
            ForEach(tiles.indices, id: \.self) { position in
                card(tiles[position], at: position)
            }
        }
        .animation(.spring(duration: 0.3), value: tiles.count)
    }

    private func card(_ tile: MemoryTile, at position: Int) -> some View {
        Button { flip(position) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tile.faceUp || tile.matched
                          ? Color.white.opacity(0.24)
                          : Palette.accent.opacity(0.32))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(tile.matched ? 0.16 : 0.42), lineWidth: 1)
                if tile.faceUp || tile.matched {
                    Image(systemName: tile.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(tile.matched ? 0.5 : 1))
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(tile.faceUp || tile.matched ? 1 : 0.94)
            .opacity(cleared && !tile.matched ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(locked || tile.faceUp || tile.matched)
        .animation(.spring(duration: 0.28), value: tile.faceUp)
    }

    // MARK: 规则

    private func startRound(_ next: Int) {
        let pairs = min(max(1, pairCount), MemoryArt.symbols.count)
        let picked = Array(MemoryArt.symbols.shuffled().prefix(pairs))
        var deck: [MemoryTile] = []
        for symbol in picked {
            deck.append(MemoryTile(symbol: symbol))
            deck.append(MemoryTile(symbol: symbol))
        }
        round = next
        tiles = deck.shuffled()
        pairsTotal = max(1, deck.count / 2)
        pending = []
        pairsDone = 0
        misses = 0
        locked = false
    }

    private func flip(_ position: Int) {
        guard !locked, tiles.indices.contains(position) else { return }
        guard !tiles[position].matched, !tiles[position].faceUp else { return }
        guard pending.count < 2 else { return }

        var current = pending
        current.append(position)
        var deck = tiles
        deck[position].faceUp = true
        tiles = deck
        pending = current

        guard current.count == 2 else { return }
        pending = []
        let first = current[0]
        let second = current[1]
        locked = true

        if tiles[first].symbol == tiles[second].symbol {
            pairsDone += 1
            Task {
                try? await Task.sleep(for: .seconds(0.32))
                seal(first, second)
                locked = false
                if pairsDone >= pairsTotal { finishRound() }
            }
        } else {
            misses += 1
            Task {
                try? await Task.sleep(for: .seconds(0.9))
                close(first, second)
                locked = false
            }
        }
    }

    /// 配对成功：整组重排写入，避免对 @State 数组做就地改
    private func seal(_ first: Int, _ second: Int) {
        var deck = tiles
        for position in [first, second] where deck.indices.contains(position) {
            deck[position].matched = true
            deck[position].faceUp = false
        }
        tiles = deck
    }

    private func close(_ first: Int, _ second: Int) {
        var deck = tiles
        for position in [first, second] where deck.indices.contains(position) {
            deck[position].faceUp = false
        }
        tiles = deck
    }

    private func finishRound() {
        guard round < totalRounds else {
            done()
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            startRound(round + 1)
        }
    }
}

// MARK: - 3. 找不同符号

private struct SymbolPair {
    let base: String
    let odd: String
    let level: Int
}

private enum SymbolArt {
    /// base 铺满格子，odd 混在里面；level 越高越像，按难度放宽取样池
    static let pairs: [SymbolPair] = [
        SymbolPair(base: "circle.fill", odd: "square.fill", level: 1),
        SymbolPair(base: "star.fill", odd: "sun.max.fill", level: 1),
        SymbolPair(base: "heart.fill", odd: "flame.fill", level: 1),
        SymbolPair(base: "lock.fill", odd: "lock.open.fill", level: 1),
        SymbolPair(base: "bell.fill", odd: "bell.slash.fill", level: 1),
        SymbolPair(base: "flag.fill", odd: "flag.slash.fill", level: 1),
        SymbolPair(base: "drop.fill", odd: "cloud.rain.fill", level: 1),
        SymbolPair(base: "leaf.fill", odd: "tree.fill", level: 2),
        SymbolPair(base: "play.fill", odd: "pause.fill", level: 2),
        SymbolPair(base: "plus.circle.fill", odd: "minus.circle.fill", level: 2),
        SymbolPair(base: "doc.fill", odd: "doc.on.doc.fill", level: 2),
        SymbolPair(base: "envelope.fill", odd: "envelope.open.fill", level: 2),
        SymbolPair(base: "hare.fill", odd: "tortoise.fill", level: 2),
        SymbolPair(base: "camera.fill", odd: "camera.on.rectangle.fill", level: 3),
        SymbolPair(base: "person.fill", odd: "person.crop.circle.fill", level: 3),
        SymbolPair(base: "square.and.arrow.up.fill", odd: "square.and.arrow.down.fill", level: 3),
        SymbolPair(base: "arrow.up.circle.fill", odd: "arrow.down.circle.fill", level: 3),
        SymbolPair(base: "hand.thumbsup.fill", odd: "hand.thumbsdown.fill", level: 3),
        SymbolPair(base: "checkmark.circle.fill", odd: "xmark.circle.fill", level: 4),
        SymbolPair(base: "sun.max.fill", odd: "sun.min.fill", level: 4),
        SymbolPair(base: "cloud.rain.fill", odd: "cloud.drizzle.fill", level: 5),
        SymbolPair(base: "circle.lefthalf.filled", odd: "circle.fill", level: 5)
    ]

    static func pick(difficulty: Int) -> SymbolPair {
        let pool = pairs.filter { $0.level <= clamped(difficulty, 1, 5) }
        return pool.randomElement() ?? pairs[0]
    }
}

private struct SymbolCell: Identifiable {
    let id = UUID()
    let symbol: String
}

struct SymbolMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var cells: [SymbolCell] = []
    @State private var pair: SymbolPair?
    @State private var round = 1
    @State private var mistakes = 0
    @State private var wrongCell: UUID?
    @State private var locked = false

    private var cellCount: Int { 4 + clamped(config.difficulty, 1, 5) }
    private var columns: Int { cellCount <= 4 ? 2 : 3 }
    private var totalRounds: Int { max(1, config.rounds) }
    private var oddSymbol: String { pair?.odd ?? "star.fill" }

    var body: some View {
        VStack(spacing: 14) {
            MissionStrip(text: "\(cellCount) 个里有 1 个长得不一样",
                         systemImage: "circle.dotted",
                         badge: totalRounds > 1 ? "第 \(clamped(round, 1, totalRounds))/\(totalRounds) 轮" : nil,
                         badgeTint: Palette.cool.opacity(0.45))
            HStack(spacing: 10) {
                Text("共 \(totalRounds) 轮").glassChip()
                Text("点错 \(mistakes)").glassChip(tint: Color.red.opacity(0.4))
                Spacer()
                Text(MissionConfig.difficultyName(config.difficulty)).glassChip(tint: Palette.accent.opacity(0.45))
            }
            board
            Spacer(minLength: 0)
            MissionHint(text: "点中那个不同的就进下一轮，点错本轮重来", systemImage: "lightbulb")
        }
        .task {
            if cells.isEmpty { dealRound(1) }
        }
    }

    private var board: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns),
                  spacing: 10) {
            ForEach(cells) { cell in
                slot(cell)
            }
        }
    }

    private func slot(_ cell: SymbolCell) -> some View {
        Button { tap(cell) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cellFill(for: cell))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.34), lineWidth: 1)
                Image(systemName: cell.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(wrongCell == cell.id ? 0.95 : 1)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .animation(.spring(duration: 0.25), value: wrongCell)
    }

    private func cellFill(for cell: SymbolCell) -> Color {
        if wrongCell == cell.id { return Color.red.opacity(0.6) }
        return Color.white.opacity(0.13)
    }

    // MARK: 规则

    private func dealRound(_ next: Int) {
        let chosen = SymbolArt.pick(difficulty: config.difficulty)
        let count = cellCount
        var deck: [SymbolCell] = (0..<max(2, count)).map { _ in SymbolCell(symbol: chosen.base) }
        let oddIndex = Int.random(in: 0..<deck.count)
        deck[oddIndex] = SymbolCell(symbol: chosen.odd)
        pair = chosen
        cells = deck
        round = next
        wrongCell = nil
        locked = false
    }

    private func tap(_ cell: SymbolCell) {
        guard !locked else { return }
        if cell.symbol == oddSymbol {
            locked = true
            wrongCell = nil
            if round >= totalRounds {
                done()
                return
            }
            Task {
                try? await Task.sleep(for: .seconds(0.45))
                dealRound(round + 1)
            }
        } else {
            mistakes += 1
            wrongCell = cell.id
            locked = true
            Task {
                try? await Task.sleep(for: .seconds(0.75))
                dealRound(round)
            }
        }
    }
}

// MARK: - 4. 点击挑战

struct TapMissionView: View {
    let config: MissionConfig
    let done: () -> Void

    @State private var progress = 0
    @State private var misses = 0
    @State private var spot = CGPoint.zero
    @State private var placed = false
    @State private var wrongFlash = false
    @State private var finished = false

    private var total: Int { max(1, config.targetCount) }
    private var level: Int { clamped(config.difficulty, 1, 5) }
    private var diameter: CGFloat { CGFloat(78 - level * 8) }
    private var penalty: Int { level >= 4 ? 2 : 1 }

    var body: some View {
        VStack(spacing: 14) {
            MissionStrip(text: "点亮点，点空要扣次数",
                         systemImage: "hand.tap.fill",
                         badge: "点空 \(misses)",
                         badgeTint: misses > 0 ? Color.red.opacity(0.4) : nil)
            MissionCounter(current: min(progress, total), target: total, unit: "次")
            board
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            MissionHint(text: "难度 \(MissionConfig.difficultyName(config.difficulty))：靶心越小、落点越飘",
                        systemImage: "lightbulb")
        }
    }

    private var board: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Palette.cool.opacity(0.14))
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(wrongFlash ? 0.9 : 0.28),
                            lineWidth: wrongFlash ? 3 : 1)
                marks
                target
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                hit(at: value.location, in: proxy.size)
            })
            .onAppear {
                placeIfNeeded(in: proxy.size)
            }
        }
    }

    /// 靶区里的装饰网格，给玻璃一点可折射的东西
    private var marks: some View {
        Canvas { context, size in
            let step: CGFloat = 34
            var x: CGFloat = step
            while x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
                x += step
            }
            var y: CGFloat = step
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
                y += step
            }
        }
    }

    private var target: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.45), lineWidth: 2)
                .frame(width: diameter + 18, height: diameter + 18)
            Circle()
                .fill(RadialGradient(colors: [Color.white, Palette.accent],
                                     center: .center, startRadius: 1, endRadius: diameter / 2))
                .frame(width: diameter, height: diameter)
            Circle()
                .stroke(.white.opacity(0.8), lineWidth: 2)
                .frame(width: diameter, height: diameter)
        }
        .position(x: spot.x, y: spot.y)
        .animation(.spring(duration: 0.28), value: spot)
        .opacity(placed ? 1 : 0)
    }

    // MARK: 规则

    private func placeIfNeeded(in size: CGSize) {
        guard !placed else { return }
        placed = true
        move(in: size)
    }

    private func hit(at point: CGPoint, in size: CGSize) {
        guard !finished else { return }
        if !placed {
            placed = true
            move(in: size)
            return
        }
        let dx = point.x - spot.x
        let dy = point.y - spot.y
        let reach = diameter / 2 + 8
        if (dx * dx + dy * dy).squareRoot() <= reach {
            progress += 1
            if progress >= total {
                finished = true
                done()
                return
            }
            move(in: size)
        } else {
            misses += 1
            progress = max(0, progress - penalty)
            wrongFlash = true
            Task {
                try? await Task.sleep(for: .seconds(0.4))
                wrongFlash = false
            }
        }
    }

    private func move(in size: CGSize) {
        // 难度越高，允许的边距越小：靶子会往边缘躲
        let margin = diameter / 2 + CGFloat(max(2, 12 - level * 2))
        guard size.width > margin * 2, size.height > margin * 2 else {
            spot = CGPoint(x: size.width / 2, y: size.height / 2)
            return
        }
        spot = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)),
                       y: CGFloat.random(in: margin...(size.height - margin)))
    }
}
