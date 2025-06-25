puts "Seeding categories..."

default_categories = [
  "Groceries",
  "House Goods",
  "Eating Out",
  "Bills",
  "Services",
  "Entertainment",
  "Rides",
  "Presents",
  "Health Care Items",
  "Pets",
  "Cosmetic Products",
  "Traveling",
  "Saving",
  "Studies",
  "Other"
]

default_categories.each do |name|

  category = Category.find_or_create_by!(name: name) do |cat|
    cat.is_default = true
  end
  puts "Ensured category exists: #{category.name}"
end

puts "Seeding complete!"
