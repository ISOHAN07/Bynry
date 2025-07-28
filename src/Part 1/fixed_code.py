from decimal import Decimal, InvalidOperation
from flask import Flask, request, jsonify, url_for
from sqlalchemy import Column, Integer, String, Numeric, ForeignKey, UniqueConstraint
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import relationship
from flask_sqlalchemy import SQLAlchemy

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'postgresql://user:pass@localhost/yourdb' # a random url to a postgresql database corresponding to our actual one 
db = SQLAlchemy(app)

# Here all the models are created that are used to handle this product inventory management platform

class Product(db.Model):
    __tablename__ = 'products'

    id    = Column(Integer, primary_key=True)
    name  = Column(String(255), nullable=False)
    sku   = Column(String(64), nullable=False, unique=True)
    price = Column(Numeric(10, 2), nullable=False)

    inventories = relationship('Inventory', back_populates='product')


class Warehouse(db.Model):
    __tablename__ = 'warehouses'

    id   = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False)

    inventories = relationship('Inventory', back_populates='warehouse')


class Inventory(db.Model):
    __tablename__ = 'inventories'
    __table_args__ = (
        UniqueConstraint('product_id', 'warehouse_id', name='uq_inventory_product_warehouse'),
    )

    id           = Column(Integer, primary_key=True)
    product_id   = Column(Integer, ForeignKey('products.id'), nullable=False)
    warehouse_id = Column(Integer, ForeignKey('warehouses.id'), nullable=False)
    quantity     = Column(Integer, nullable=False, default=0)

    product   = relationship('Product', back_populates='inventories')
    warehouse = relationship('Warehouse', back_populates='inventories')

# This is the route for posting a particular product
@app.route('/api/products', methods=['POST'])
def create_product():
    data = request.get_json(force=True)

    #1. Validating the required fields
    name = data.get('name', '').strip()
    sku  = data.get('sku', '').strip()
    if not name or not sku:
        return jsonify({"error": "Both 'name' and 'sku' are required"}), 400
    
    #2. Validate and parse the 'price'
    raw_price = data.get('price')
    try:
        price = Decimal(str(raw_price))
    except (InvalidOperation, TypeError):
        return jsonify({"error": "'price' must be a valid decimal"}), 400
    if price < 0:
        return jsonify({"error": "'price' must be non‑negative"}), 400
    
    #3. After passing all the checks, if the checks pass then create the product
    try:
        product = Product(name=name, sku=sku, price=price)
        db.session.add(product)
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return jsonify({"error": "SKU already exists"}), 409
    except Exception:
        db.session.rollback()
        return jsonify({"error": "Internal server error"}), 500
    
    #4. Return response with proper HTTP semantics
    return (
        jsonify({
            "message": "Product created",
            "product_id": product.id
        }),
        201,
        {"Location": url_for('get_product', product_id=product.id, _external=True)}
    )

# this is the route for posting a product into the inventory
@app.route('/api/inventory', methods=['POST'])
def add_inventory():
    data = request.get_json(force=True)

    #1. Validate all the required ids
    pid = data.get('product_id')
    wid = data.get('warehouse_id')
    if not pid or not wid:
        return jsonify({"error": "'product_id' and 'warehouse_id' are required"}), 400
    
    #2. Perform the integrity check to check whether the product_id or the warehouse_id exist or not
    product   = Product.query.get(pid)
    warehouse = Warehouse.query.get(wid)
    if not product or not warehouse:
        return jsonify({"error": "Invalid 'product_id' or 'warehouse_id'"}), 400
    
    #3. Validates if the quantity is valid or not i.e the quantity is an integer value or not
    raw_qty = data.get('quantity', 0)
    try:
        qty = int(raw_qty)
    except (TypeError, ValueError):
        return jsonify({"error": "'quantity' must be an integer"}), 400
    if qty < 0:
        return jsonify({"error": "'quantity' must be non‑negative"}), 400
    
    #4. Upsert the inventory after performing all the validations
    inv = Inventory.query.filter_by(product_id=pid, warehouse_id=wid).first()
    if not inv:
        inv = Inventory(product_id=pid, warehouse_id=wid, quantity=qty)
        db.session.add(inv)
    else:
        inv.quantity = qty

    #5. Commit and handle errors
    try:
        db.session.commit()
    except Exception:
        db.session.rollback()
        return jsonify({"error": "Internal server error"}), 500

    return jsonify({
        "message": "Inventory updated",
        "inventory_id": inv.id,
        "quantity": inv.quantity
    }), 200

# This is the route for getting a particular product by using the product_id
@app.route('/api/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    product = Product.query.get_or_404(product_id)
    # Aggregate total across warehouses
    total_stock = sum(inv.quantity for inv in product.inventories)
    return jsonify({
        "id": product.id,
        "name": product.name,
        "sku": product.sku,
        "price": str(product.price),
        "total_stock": total_stock,
        "warehouses": [
            {"warehouse_id": inv.warehouse_id, "quantity": inv.quantity}
            for inv in product.inventories
        ]
    })

# This py file is now ready for posting and getting products from the inventory
if __name__ == '__main__':
    app.run(debug=True)
