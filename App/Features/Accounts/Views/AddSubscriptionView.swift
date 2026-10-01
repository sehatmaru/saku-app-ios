import SwiftUI

/// Full-screen "Tagihan berulang" form (design 1c): wallet-coloured panel with the amount and the
/// month's billing days, rows for name, category and day, and a numpad.
struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let account: Account
    /// The wallet's subscriptions when the form opened, for the totals and the billing-day ticks;
    /// kept fixed so the reload after saving doesn't count the new one twice.
    @State private var subscriptions: [CardSubscription]
    let existing: CardSubscription?
    let onSave: () -> Void

    private enum Row { case name, category, day }

    @State private var amount = 0
    @State private var nameText = ""
    @State private var selectedCategory: Category?
    @State private var billingDay: Int
    @State private var bump = false
    @State private var shake: CGFloat = 0
    @State private var flash: Row?
    @State private var hasEntered = false
    @State private var isDone = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showCategorySheet = false
    @State private var showDaySheet = false
    @State private var showDeleteConfirm = false
    @FocusState private var isNameFocused: Bool

    init(categories: [Category], account: Account, subscriptions: [CardSubscription],
         existing: CardSubscription? = nil, day: Int? = nil, onSave: @escaping () -> Void) {
        self.categories = categories
        self.account = account
        _subscriptions = State(initialValue: subscriptions)
        self.existing = existing
        self.onSave = onSave
        let existingDay = existing?.nextBillingDateAsDate.map { Calendar.current.component(.day, from: $0) }
        _billingDay = State(initialValue: existingDay ?? day ?? Calendar.current.component(.day, from: Date()))
    }

    // MARK: Derived

    private var color: Color { account.walletColor }
    private var expenseCategories: [Category] { categories.filter { $0.type == .expense } }
    private var frequency: CardSubscription.Frequency { existing?.frequency ?? .monthly }
    private var others: [CardSubscription] { subscriptions.filter { $0.id != existing?.id } }
    private var othersMonthly: Double { others.filter(\.isActive).reduce(0) { $0 + $1.monthlyAmount } }
    private var newMonthly: Double { frequency == .yearly ? Double(amount) / 12 : Double(amount) }
    private var totalAfter: Double { othersMonthly + newMonthly }

    private func day(of sub: CardSubscription) -> Int? {
        sub.nextBillingDateAsDate.map { Calendar.current.component(.day, from: $0) }
    }
    private var busyDays: Set<Int> { Set(others.compactMap(day(of:))) }
    private var sameDayCount: Int { others.filter { day(of: $0) == billingDay }.count }

    /// Credit cards only: the month's bills wouldn't fit in what's left of the limit.
    private var isOverLimit: Bool {
        guard amount > 0, let available = account.availableCredit else { return false }
        return totalAfter > available
    }

    private var isValid: Bool {
        amount > 0 && !isOverLimit && !nameText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var chipLogo: String? {
        if let network = account.networkId { return network == "gpn" ? nil : network }
        return account.brandLogo
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            panel
            rows
                .padding(.top, 10)
                .opacity(isDone ? 0 : 1)
                .animation(.easeOut(duration: 0.3), value: isDone)
            if let errorMessage {
                Text(errorMessage)
                    .font(.app(13))
                    .foregroundStyle(Color.appError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            } else {
                Label("Dicatat otomatis saat kamu buka Saku di tanggal ini.", systemImage: "info.circle")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .opacity(isDone ? 0 : 1)
            }
            Spacer(minLength: 12)
            // v4: Simpan sits beside the keys again; tapping it while invalid shows why.
            AmountPad(color: color, isEnabled: isValid, isSaving: isSaving, onPress: press) {
                isValid ? save() : blocked()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .sensoryFeedback(.success, trigger: isDone) { _, done in done }
        }
        .background(Color.appBackground)
        .ignoresSafeArea(.keyboard)
        .onAppear { hasEntered = true; prefill() }
        .sheet(isPresented: $showCategorySheet) { categorySheet }
        .sheet(isPresented: $showDaySheet) { daySheet }
        .confirmationDialog("Hapus tagihan ini?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Hapus tagihan", role: .destructive) { delete() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Tagihan berikutnya tidak akan dicatat lagi.")
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            navRow
            ZStack(alignment: .top) {
                panelContent
                    .opacity(isDone ? 0 : 1)
                    .offset(y: isDone ? -14 : 0)
                    .scaleEffect(isDone ? 0.97 : 1)
                    .animation(.settle(0.42), value: isDone)
                doneContent
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(height: 256)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32)
                .fill(color)
                .overlay {
                    LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0), location: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "repeat")
                        .font(.system(size: 170, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.06))
                        .offset(x: 30, y: 90)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32))
                .ignoresSafeArea(edges: .top)
        }
    }

    private var navRow: some View {
        HStack {
            Button("Batal") { dismiss() }
                .font(.app(17))
                .foregroundStyle(.white)
            Spacer()
            if let existing, !isDone {
                Menu {
                    Button(existing.isActive ? L("Jeda") : L("Aktifkan"),
                           systemImage: existing.isActive ? "pause" : "play") { togglePause() }
                    Button("Hapus", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .disabled(isSaving)
                .accessibilityLabel("Lainnya")
            }
        }
        .overlay {
            HStack(spacing: 8) {
                if existing == nil { Image(systemName: "repeat").font(.system(size: 15, weight: .bold)) }
                Text(existing == nil ? L("Tagihan berulang") : L("Ubah tagihan"))
                    .font(.app(17, weight: .semibold))
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white)
                    .frame(width: 28, height: 18)
                    .overlay {
                        if let chipLogo {
                            Image(chipLogo).resizable().scaledToFit().frame(width: 20, height: 11)
                        } else {
                            Image(systemName: account.typeSymbol)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(color)
                        }
                    }
                Text("Ditagih ke \(account.name)")
                    .font(.app(13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .frame(height: 28)
            .background(.white.opacity(0.14), in: Capsule())
            .padding(.top, 6)

            HStack(alignment: .top, spacing: 4) {
                Text("Rp")
                    .font(.app(22))
                    .opacity(0.75)
                    .padding(.top, 8)
                Text(Double(amount).formattedAsDigits())
                    .font(.app(56, weight: .light))
                    .tracking(-2)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .opacity(amount > 0 ? 1 : 0.55)
            .scaleEffect(bump ? 1.04 : 1)
            .offset(x: shake)
            .animation(.easeOut(duration: 0.12), value: bump)
            .animation(.easeOut(duration: 0.2), value: amount > 0)
            .padding(.horizontal, 24)
            .padding(.top, 18)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Total per bulan")
                        .font(.app(13))
                        .opacity(0.85)
                    Spacer()
                    Text(amount > 0 ? "\(othersMonthly.formattedAsCurrency()) → \(totalAfter.formattedAsCurrency())"
                                    : othersMonthly.formattedAsCurrency())
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(isOverLimit ? Color(hex: "FFB4AE") : .white)
                        .animation(.easeInOut(duration: 0.22), value: isOverLimit)
                }
                .monospacedDigit()

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(1...31, id: \.self) { d in
                        let isOn = d == billingDay
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isOn ? .white : busyDays.contains(d) ? .white.opacity(0.5) : .black.opacity(0.22))
                            .frame(height: isOn ? 8 : 5)
                            .animation(.spring(duration: 0.3, bounce: 0.5), value: isOn)
                    }
                }
                .frame(height: 8)
                .padding(.top, 8)

                ZStack(alignment: .topLeading) {
                    Text(sameDayCount > 0
                         ? L("Tiap tanggal %lld · sudah ada %lld tagihan di tanggal ini", billingDay, sameDayCount)
                         : L("Tiap tanggal %lld · belum ada tagihan lain", billingDay))
                        .font(.app(12))
                        .monospacedDigit()
                        .opacity(isOverLimit ? 0 : 0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    overLimitPill
                        .offset(y: -2)
                }
                .frame(height: 30)
                .padding(.top, 7)
                .animation(.easeInOut(duration: 0.22), value: isOverLimit)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
        }
    }

    private var overLimitPill: some View {
        let available = account.availableCredit ?? 0
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 15))
            Text("Melebihi sisa limit \(available.formattedAsCurrency()) · lebih \((totalAfter - available).formattedAsCurrency())")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.app(13, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color(hex: "D93025"))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .opacity(isOverLimit ? 1 : 0)
        .scaleEffect(isOverLimit ? 1 : 0.96)
        .offset(x: isOverLimit ? shake : 0, y: isOverLimit ? 0 : 6)
        .animation(.spring(duration: 0.38, bounce: 0.45), value: isOverLimit)
    }

    private var doneContent: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(.white)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(color)
                }
                .scaleEffect(isDone ? 1 : 0.4)
                .animation(.spring(duration: 0.56, bounce: 0.5), value: isDone)
            Text("Tagihan berulang tersimpan")
                .font(.app(20, weight: .semibold))
                .padding(.top, 6)
            Text(([Double(amount).formattedAsCurrency()] + (selectedCategory.map { [$0.name] } ?? []) + [L("tiap tgl %lld", billingDay)])
                .joined(separator: " · "))
                .font(.app(14))
                .opacity(0.85)
            Text("Total jadi \(totalAfter.formattedAsCurrency())/bulan")
                .font(.app(13))
                .opacity(0.75)
        }
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .opacity(isDone ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isDone)
        .allowsHitTesting(false)
    }

    // MARK: Rows

    private func flashFill(_ row: Row) -> Color {
        guard flash == row else { return .clear }
        return row == .name ? Color(light: 0xFDECEA, dark: 0x3A1D1B) : color.opacity(0.08)
    }

    private func entering<V: View>(_ view: V, index: Int) -> some View {
        view
            .opacity(hasEntered ? 1 : 0)
            .offset(y: hasEntered ? 0 : 14)
            .animation(.settle(0.5).delay(Double(index) * 0.06 + 0.2), value: hasEntered)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.app(15))
            .foregroundStyle(Color.appTextSecondary)
            .frame(width: 76, alignment: .leading)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            entering(nameRow, index: 0)
            entering(categoryRow, index: 1)
            entering(dayRow, index: 2)
        }
        .disabled(isDone)
    }

    private var nameRow: some View {
        HStack(spacing: 12) {
            label(L("Nama"))
            TextField("Contoh: Netflix", text: $nameText)
                .font(.app(16, weight: .medium))
                .foregroundStyle(Color.appText)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onChange(of: nameText) { _, new in
                    if new.count > 40 { nameText = String(new.prefix(40)) }
                }
        }
        .frame(height: 52)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .background(flashFill(.name))
        .animation(.easeOut(duration: 0.45), value: flash)
        .rowSeparator()
        .contentShape(Rectangle())
        .onTapGesture { isNameFocused = true }
    }

    private func pickerRow(_ title: String, row: Row, icon: String, iconColor: Color, value: String,
                           valueColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label(title)
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(iconColor)
                    Text(value)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .frame(height: 52)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .background(flashFill(row))
            .animation(.easeOut(duration: 0.45), value: flash)
            .rowSeparator()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private var categoryRow: some View {
        pickerRow(L("Kategori"), row: .category, icon: selectedCategory?.icon ?? "tag",
                  iconColor: selectedCategory == nil ? .appTextSecondary : color,
                  value: selectedCategory?.name ?? L("Pilih"),
                  valueColor: selectedCategory == nil ? .appTextSecondary : .appText) {
            isNameFocused = false
            showCategorySheet = true
        }
    }

    private var dayRow: some View {
        pickerRow(L("Tanggal"), row: .day, icon: "calendar", iconColor: .appTextSecondary,
                  value: L("Tiap tanggal %lld", billingDay), valueColor: .appText) {
            isNameFocused = false
            showDaySheet = true
        }
    }

    // MARK: Sheets

    private func sheetHeader(_ title: String, close: @escaping () -> Void) -> some View {
        HStack {
            Button("Batal", action: close)
                .font(.app(17))
                .foregroundStyle(Color.appPrimary)
            Spacer()
        }
        .overlay {
            Text(title)
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
        }
        .frame(height: 48)
        .padding(.horizontal, 24)
        .padding(.top, 13)
    }

    private var categorySheet: some View {
        VStack(spacing: 0) {
            sheetHeader(L("Kategori")) { showCategorySheet = false }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 18) {
                    ForEach(expenseCategories) { category in
                        let isOn = category.id == selectedCategory?.id
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) { selectedCategory = category }
                            pickThenClose(.category) { showCategorySheet = false }
                        } label: {
                            VStack(spacing: 7) {
                                Circle()
                                    .fill(isOn ? color : Color.appFill)
                                    .frame(width: 54, height: 54)
                                    .overlay {
                                        Image(systemName: category.icon ?? "tag")
                                            .font(.system(size: 22))
                                            .foregroundStyle(isOn ? Color.white : Color.appText)
                                    }
                                    .scaleEffect(isOn ? 1.08 : 1)
                                    .animation(.spring(duration: 0.32, bounce: 0.5), value: isOn)
                                Text(category.name)
                                    .font(.app(12))
                                    .foregroundStyle(isOn ? Color.appText : Color.appTextSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
        .background(Color.appBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }

    private var daySheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader(L("Tanggal tagih")) { showDaySheet = false }
            Text("Ditagih tiap bulan di tanggal yang sama, dan dicatat otomatis saat kamu buka Saku di tanggal itu. Titik = sudah ada tagihan.")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(1...31, id: \.self) { d in
                    let isOn = d == billingDay
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { billingDay = d }
                        pickThenClose(.day) { showDaySheet = false }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(d)")
                                .font(.app(16, weight: isOn ? .semibold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(isOn ? Color.white : Color.appText)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(isOn ? color : .clear))
                                .scaleEffect(isOn ? 1.06 : 1)
                                .animation(.spring(duration: 0.38, bounce: 0.45), value: isOn)
                            Circle()
                                .fill(Color.appPrimary)
                                .frame(width: 4, height: 4)
                                .opacity(busyDays.contains(d) ? 1 : 0)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(busyDays.contains(d) ? L("Tanggal %lld, sudah ada tagihan", d) : L("Tanggal %lld", d))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .background(Color.appBackground)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }

    /// Closes a picker 200ms after the pick, then flashes the row it filled.
    private func pickThenClose(_ row: Row, close: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            close()
            try? await Task.sleep(for: .milliseconds(250))
            flashRow(row)
        }
    }

    private func flashRow(_ row: Row) {
        flash = row
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            if flash == row { flash = nil }
        }
    }

    // MARK: Logic

    private func press(_ key: String) {
        guard !isDone, let next = NumberPad.apply(key, to: amount) else { return }
        isNameFocused = false
        withAnimation(.easeOut(duration: 0.14)) { amount = next }
        bump = true
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            bump = false
        }
    }

    private func shakeAmount() {
        Task {
            for value: CGFloat in [-10, 9, -6, 4, 0] {
                withAnimation(.easeInOut(duration: 0.06)) { shake = value }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func prefill() {
        guard let existing else { return }
        nameText = existing.name
        amount = Int(existing.amount)
        selectedCategory = expenseCategories.first { $0.id == existing.categoryId }
    }

    /// Next date on `billingDay` from today (today included), clamped to short months.
    /// When editing and the day wasn't changed, the stored date stays (yearly ones keep their month).
    private var nextBillingDate: Date {
        if let date = existing?.nextBillingDateAsDate, Calendar.current.component(.day, from: date) == billingDay {
            return date
        }
        return Self.nextOccurrence(ofDay: billingDay, from: Date())
    }

    static func nextOccurrence(ofDay day: Int, from now: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: today),
                  let range = calendar.range(of: .day, in: .month, for: month) else { continue }
            var parts = calendar.dateComponents([.year, .month], from: month)
            parts.day = min(day, range.count)
            if let date = calendar.date(from: parts), date >= today { return date }
        }
        return today
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// The chosen category, or "Lainnya" when none was picked.
    private var categoryId: String? {
        (selectedCategory ?? expenseCategories.first { $0.name.localizedCaseInsensitiveCompare("Lainnya") == .orderedSame })?.id
    }

    /// Why the slider won't go: shake for no amount or over the limit, flash the name when it's missing.
    private func blocked() {
        guard !isDone, !isSaving else { return }
        if amount == 0 { shakeAmount(); return }
        if isOverLimit {
            shakeAmount()
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        if nameText.trimmingCharacters(in: .whitespaces).isEmpty {
            flashRow(.name)
            isNameFocused = true
        }
    }

    private func save() {
        guard !isDone, !isSaving else { return }
        guard isValid else { blocked(); return }
        isSaving = true
        errorMessage = nil
        let name = nameText.trimmingCharacters(in: .whitespaces)
        let value = Double(amount)
        let nextDate = dateString(nextBillingDate)
        Task {
            do {
                await NotificationManager.shared.requestPermissionIfNeeded()
                let saved: CardSubscription
                if let existing {
                    saved = try await SupabaseRepository.shared.updateSubscription(
                        id: existing.id, name: name, amount: value, frequency: frequency,
                        nextBillingDate: nextDate, isActive: existing.isActive, categoryId: categoryId,
                        note: existing.note, previousAmount: existing.amount
                    )
                } else {
                    saved = try await SupabaseRepository.shared.createSubscription(
                        accountId: account.id, name: name, amount: value, frequency: .monthly,
                        nextBillingDate: nextDate, categoryId: categoryId, note: nil
                    )
                }
                await NotificationManager.shared.schedule(for: saved)
                isSaving = false
                isNameFocused = false
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                isDone = true
                try? await Task.sleep(for: .milliseconds(1500))
                onSave()
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                isSaving = false
                errorMessage = L("Gagal menyimpan. Coba lagi.")
            }
        }
    }

    private func togglePause() {
        guard let existing else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let saved = try await SupabaseRepository.shared.updateSubscription(
                    id: existing.id, name: existing.name, amount: existing.amount, frequency: existing.frequency,
                    nextBillingDate: existing.nextBillingDate, isActive: !existing.isActive,
                    categoryId: existing.categoryId, note: existing.note
                )
                if saved.isActive {
                    await NotificationManager.shared.schedule(for: saved)
                } else {
                    await NotificationManager.shared.cancel(for: existing)
                }
                finish()
            } catch is CancellationError {
                return
            } catch {
                isSaving = false
                errorMessage = L("Gagal menyimpan. Coba lagi.")
            }
        }
    }

    private func delete() {
        guard let existing else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SupabaseRepository.shared.deleteSubscription(id: existing.id)
                await NotificationManager.shared.cancel(for: existing)
                finish()
            } catch is CancellationError {
                return
            } catch {
                isSaving = false
                errorMessage = L("Gagal menghapus. Coba lagi.")
            }
        }
    }

    private func finish() {
        isSaving = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSave()
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        dismiss()
    }
}
