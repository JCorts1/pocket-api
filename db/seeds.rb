puts "Deleting old data..."
Expense.destroy_all
Category.destroy_all

puts "Creating default categories..."

categories = [
  "Food & Drinks",
  "Shopping",
  "Housing",
  "Transportation",
  "Health",
  "Entertainment",
  "Utilities",
  "Other"
]

categories.each do |cat_name|
  Category.create!(name: cat_name, is_default: true)
  puts "Created category: #{cat_name}"
end

puts "Seeding complete!"
