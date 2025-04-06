from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from datetime import datetime
import os
import logging
import json

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Configure the database
db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'currency_changer.db')
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{db_path}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# Define models
class Currency(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    code = db.Column(db.String(3), unique=True, nullable=False)
    quantity = db.Column(db.Float, default=0.0)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow)
    default_buy_rate = db.Column(db.Float, default=0.0)
    default_sell_rate = db.Column(db.Float, default=0.0)

    def to_dict(self):
        return {
            'id': self.id,
            'code': self.code,
            'quantity': self.quantity,
            'updated_at': self.updated_at.isoformat(),
            'default_buy_rate': self.default_buy_rate,
            'default_sell_rate': self.default_sell_rate
        }

class History(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    currency_code = db.Column(db.String(3), nullable=False)
    operation_type = db.Column(db.String(20), nullable=False)
    rate = db.Column(db.Float, nullable=False)
    quantity = db.Column(db.Float, nullable=False)
    total = db.Column(db.Float, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'currency_code': self.currency_code,
            'operation_type': self.operation_type,
            'rate': self.rate,
            'quantity': self.quantity,
            'total': self.total,
            'created_at': self.created_at.isoformat()
        }

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password = db.Column(db.String(100), nullable=False)
    role = db.Column(db.String(20), default='user')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'username': self.username,
            'password': self.password,
            'role': self.role,
            'created_at': self.created_at.isoformat()
        }

# Initialize database tables and data (after model definitions)
with app.app_context():
    db.create_all()
    
    # Add initial data if not exists
    som_currency = Currency.query.filter_by(code='SOM').first()
    if som_currency is None:
        # Create new SOM currency if it doesn't exist
        default_currency = Currency(
            code='SOM',
            quantity=0.0,
            default_buy_rate=0.0,
            default_sell_rate=0.0
        )
        db.session.add(default_currency)
    else:
        # Ensure SOM currency has the correct quantity
        som_currency.quantity = 0.0
    
    # Add admin user if not exists
    if User.query.filter_by(username='a').first() is None:
        admin_user = User(
            username='a',
            password='a',
            role='admin'
        )
        db.session.add(admin_user)
    
    db.session.commit()
    logger.info("Database initialized with default data")

# API Routes

# Currency endpoints
@app.route('/api/currencies', methods=['GET'])
def get_all_currencies():
    currencies = Currency.query.all()
    return jsonify([currency.to_dict() for currency in currencies])

@app.route('/api/currencies/<string:code>', methods=['GET'])
def get_currency(code):
    currency = Currency.query.filter_by(code=code).first()
    if currency:
        return jsonify(currency.to_dict())
    return jsonify({"error": "Currency not found"}), 404

@app.route('/api/currencies', methods=['POST'])
def create_currency():
    data = request.json
    if not data or 'code' not in data:
        return jsonify({"error": "Invalid data"}), 400
    
    existing = Currency.query.filter_by(code=data['code']).first()
    if existing:
        return jsonify({"error": "Currency already exists"}), 409
    
    new_currency = Currency(
        code=data['code'],
        quantity=float(data.get('quantity', 0.0)),
        default_buy_rate=float(data.get('default_buy_rate', 0.0)),
        default_sell_rate=float(data.get('default_sell_rate', 0.0)),
        updated_at=datetime.utcnow()
    )
    
    db.session.add(new_currency)
    db.session.commit()
    return jsonify(new_currency.to_dict()), 201

@app.route('/api/currencies/<int:id>', methods=['PUT'])
def update_currency(id):
    currency = Currency.query.get(id)
    if not currency:
        return jsonify({"error": "Currency not found"}), 404
    
    data = request.json
    if 'code' in data:
        currency.code = data['code']
    if 'quantity' in data:
        currency.quantity = float(data['quantity'])
    if 'default_buy_rate' in data:
        currency.default_buy_rate = float(data['default_buy_rate'])
    if 'default_sell_rate' in data:
        currency.default_sell_rate = float(data['default_sell_rate'])
    
    currency.updated_at = datetime.utcnow()
    db.session.commit()
    return jsonify(currency.to_dict())

@app.route('/api/currencies/<string:code>/quantity', methods=['PUT'])
def update_currency_quantity(code):
    currency = Currency.query.filter_by(code=code).first()
    if not currency:
        return jsonify({"error": "Currency not found"}), 404
    
    data = request.json
    if 'quantity' in data:
        currency.quantity = float(data['quantity'])
        currency.updated_at = datetime.utcnow()
        db.session.commit()
        return jsonify(currency.to_dict())
    
    return jsonify({"error": "Quantity not provided"}), 400

@app.route('/api/currencies/<int:id>', methods=['DELETE'])
def delete_currency(id):
    currency = Currency.query.get(id)
    if not currency:
        return jsonify({"error": "Currency not found"}), 404
    
    db.session.delete(currency)
    db.session.commit()
    return jsonify({"message": "Currency deleted successfully"})

# History endpoints
@app.route('/api/history', methods=['GET'])
def get_history():
    limit = request.args.get('limit', type=int)
    currency_code = request.args.get('currency_code')
    operation_type = request.args.get('operation_type')
    
    query = History.query
    
    if currency_code:
        query = query.filter_by(currency_code=currency_code)
    if operation_type:
        query = query.filter_by(operation_type=operation_type)
    
    query = query.order_by(History.created_at.desc())
    
    if limit:
        query = query.limit(limit)
    
    entries = query.all()
    return jsonify([entry.to_dict() for entry in entries])

@app.route('/api/history/filter', methods=['GET'])
def filter_history():
    from_date = request.args.get('from_date')
    to_date = request.args.get('to_date')
    currency_code = request.args.get('currency_code')
    operation_type = request.args.get('operation_type')
    
    if not from_date or not to_date:
        return jsonify({"error": "Both from_date and to_date are required"}), 400
    
    try:
        from_date_obj = datetime.fromisoformat(from_date.replace('Z', '+00:00'))
        to_date_obj = datetime.fromisoformat(to_date.replace('Z', '+00:00'))
    except ValueError:
        return jsonify({"error": "Invalid date format"}), 400
    
    query = History.query.filter(
        History.created_at >= from_date_obj,
        History.created_at <= to_date_obj
    )
    
    if currency_code:
        query = query.filter_by(currency_code=currency_code)
    if operation_type:
        query = query.filter_by(operation_type=operation_type)
    
    entries = query.order_by(History.created_at.desc()).all()
    return jsonify([entry.to_dict() for entry in entries])

@app.route('/api/history', methods=['POST'])
def create_history():
    data = request.json
    if not data or not all(key in data for key in ['currency_code', 'operation_type', 'rate', 'quantity', 'total']):
        return jsonify({"error": "Invalid data"}), 400
    
    new_entry = History(
        currency_code=data['currency_code'],
        operation_type=data['operation_type'],
        rate=float(data['rate']),
        quantity=float(data['quantity']),
        total=float(data['total']),
        created_at=datetime.utcnow()
    )
    
    db.session.add(new_entry)
    db.session.commit()
    return jsonify(new_entry.to_dict()), 201

@app.route('/api/history/<int:id>', methods=['PUT'])
def update_history(id):
    entry = History.query.get(id)
    if not entry:
        return jsonify({"error": "History entry not found"}), 404
    
    data = request.json
    if 'currency_code' in data:
        entry.currency_code = data['currency_code']
    if 'operation_type' in data:
        entry.operation_type = data['operation_type']
    if 'rate' in data:
        entry.rate = float(data['rate'])
    if 'quantity' in data:
        entry.quantity = float(data['quantity'])
    if 'total' in data:
        entry.total = float(data['total'])
    if 'created_at' in data:
        try:
            entry.created_at = datetime.fromisoformat(data['created_at'].replace('Z', '+00:00'))
        except ValueError:
            return jsonify({"error": "Invalid date format"}), 400
    
    db.session.commit()
    return jsonify(entry.to_dict())

@app.route('/api/history/<int:id>', methods=['DELETE'])
def delete_history(id):
    entry = History.query.get(id)
    if not entry:
        return jsonify({"error": "History entry not found"}), 404
    
    db.session.delete(entry)
    db.session.commit()
    return jsonify({"message": "History entry deleted successfully"})

# User endpoints
@app.route('/api/users/login', methods=['POST'])
def login():
    data = request.json
    if not data or 'username' not in data or 'password' not in data:
        return jsonify({"error": "Username and password required"}), 400
    
    user = User.query.filter_by(username=data['username'], password=data['password']).first()
    if user:
        return jsonify(user.to_dict())
    
    return jsonify({"error": "Invalid credentials"}), 401

@app.route('/api/users', methods=['GET'])
def get_all_users():
    users = User.query.all()
    return jsonify([user.to_dict() for user in users])

@app.route('/api/users', methods=['POST'])
def create_user():
    data = request.json
    if not data or not all(key in data for key in ['username', 'password']):
        return jsonify({"error": "Username and password required"}), 400
    
    existing = User.query.filter_by(username=data['username']).first()
    if existing:
        return jsonify({"error": "Username already exists"}), 409
    
    new_user = User(
        username=data['username'],
        password=data['password'],
        role=data.get('role', 'user')
    )
    
    db.session.add(new_user)
    db.session.commit()
    return jsonify(new_user.to_dict()), 201

@app.route('/api/users/<int:id>', methods=['PUT'])
def update_user(id):
    user = User.query.get(id)
    if not user:
        return jsonify({"error": "User not found"}), 404
    
    data = request.json
    if 'username' in data:
        # Check if username already exists
        if data['username'] != user.username and User.query.filter_by(username=data['username']).first():
            return jsonify({"error": "Username already exists"}), 409
        user.username = data['username']
    
    if 'password' in data:
        user.password = data['password']
    
    if 'role' in data:
        user.role = data['role']
    
    db.session.commit()
    return jsonify(user.to_dict())

@app.route('/api/users/<int:id>', methods=['DELETE'])
def delete_user(id):
    user = User.query.get(id)
    if not user:
        return jsonify({"error": "User not found"}), 404
    
    db.session.delete(user)
    db.session.commit()
    return jsonify({"message": "User deleted successfully"})

@app.route('/api/users/check-username', methods=['POST'])
def check_username():
    data = request.json
    if not data or 'username' not in data:
        return jsonify({"error": "Username required"}), 400
    
    exists = User.query.filter_by(username=data['username']).first() is not None
    return jsonify({"exists": exists})

# System endpoints
@app.route('/api/system/reset', methods=['POST'])
def reset_data():
    try:
        # Set all currency quantities to zero
        currencies = Currency.query.all()
        for currency in currencies:
            currency.quantity = 0.0
            currency.updated_at = datetime.utcnow()
        
        # Delete all history
        History.query.delete()
        
        db.session.commit()
        return jsonify({"message": "Data reset successfully. Transaction history deleted and all currency balances set to zero."})
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

@app.route('/api/system/currency-summary', methods=['GET'])
def currency_summary():
    currencies = Currency.query.all()
    summary = {}
    
    for currency in currencies:
        summary[currency.code] = {
            'quantity': currency.quantity,
            'updated_at': currency.updated_at.isoformat()
        }
    
    return jsonify(summary)

@app.route('/api/system/history-codes', methods=['GET'])
def history_codes():
    distinct_codes = db.session.query(History.currency_code).distinct().all()
    return jsonify([code[0] for code in distinct_codes])

@app.route('/api/system/history-types', methods=['GET'])
def history_types():
    distinct_types = db.session.query(History.operation_type).distinct().all()
    return jsonify([type[0] for type in distinct_types])

@app.route('/api/system/exchange', methods=['POST'])
def exchange():
    data = request.json
    if not data or not all(key in data for key in ['currency_code', 'operation_type', 'rate', 'quantity', 'total']):
        return jsonify({"error": "Required fields missing"}), 400
    
    currency_code = data['currency_code']
    operation_type = data['operation_type']
    rate = float(data['rate'])
    quantity = float(data['quantity'])
    total = float(data['total'])
    
    # Validate the data
    if rate <= 0 or quantity <= 0 or total <= 0:
        return jsonify({"error": "Invalid numbers"}), 400
    
    if total != round(rate * quantity, 2):
        return jsonify({"error": "Total does not match rate * quantity"}), 400
    
    try:
        # Get the currency
        currency = Currency.query.filter_by(code=currency_code).first()
        if not currency:
            return jsonify({"error": "Currency not found"}), 404
        
        # Get SOM currency
        som = Currency.query.filter_by(code='SOM').first()
        if not som:
            return jsonify({"error": "SOM currency not found"}), 404
        
        # Update currency quantities
        if operation_type == 'Purchase':
            # We buy foreign currency, spending SOM
            if som.quantity < total:
                return jsonify({"error": "Not enough SOM for purchase"}), 400
            
            som.quantity -= total
            currency.quantity += quantity
        elif operation_type == 'Sale':
            # We sell foreign currency, receiving SOM
            if currency.quantity < quantity:
                return jsonify({"error": f"Not enough {currency_code} for sale"}), 400
            
            currency.quantity -= quantity
            som.quantity += total
        else:
            return jsonify({"error": "Invalid operation type"}), 400
        
        # Record the transaction
        new_entry = History(
            currency_code=currency_code,
            operation_type=operation_type,
            rate=rate,
            quantity=quantity,
            total=total,
            created_at=datetime.utcnow()
        )
        
        db.session.add(new_entry)
        db.session.commit()
        
        return jsonify({
            "message": "Exchange completed successfully",
            "transaction": new_entry.to_dict(),
            "currency": currency.to_dict(),
            "som": som.to_dict()
        })
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": str(e)}), 500

# Analytics endpoints
@app.route('/api/analytics/daily-data', methods=['GET'])
def daily_data():
    from_date = request.args.get('from_date')
    to_date = request.args.get('to_date')
    currency_code = request.args.get('currency_code')
    
    if not from_date or not to_date:
        return jsonify({"error": "Both from_date and to_date are required"}), 400
    
    try:
        from_date_obj = datetime.fromisoformat(from_date.replace('Z', '+00:00'))
        to_date_obj = datetime.fromisoformat(to_date.replace('Z', '+00:00'))
    except ValueError:
        return jsonify({"error": "Invalid date format"}), 400
    
    # Get history entries within date range
    query = History.query.filter(
        History.created_at >= from_date_obj,
        History.created_at <= to_date_obj
    )
    
    if currency_code and currency_code != 'ALL':
        query = query.filter_by(currency_code=currency_code)
    
    entries = query.all()
    
    # Calculate daily data with proper profit calculation
    daily_data = {}
    daily_rates = {}  # Store average rates for each currency per day
    
    # First pass: Calculate daily average rates for purchases
    for entry in entries:
        day = entry.created_at.strftime('%Y-%m-%d')
        currency = entry.currency_code
        
        if day not in daily_rates:
            daily_rates[day] = {}
        if currency not in daily_rates[day]:
            daily_rates[day][currency] = {
                'total_purchased': 0.0,
                'total_purchase_amount': 0.0,
                'total_sold': 0.0,
                'total_sale_amount': 0.0
            }
            
        if entry.operation_type == 'Purchase':
            daily_rates[day][currency]['total_purchased'] += entry.quantity
            daily_rates[day][currency]['total_purchase_amount'] += entry.total
        elif entry.operation_type == 'Sale':
            daily_rates[day][currency]['total_sold'] += entry.quantity
            daily_rates[day][currency]['total_sale_amount'] += entry.total
    
    # Second pass: Calculate daily totals and profits
    for day, currencies in daily_rates.items():
        if day not in daily_data:
            daily_data[day] = {
                'day': day,
                'purchases': 0.0,
                'sales': 0.0,
                'profit': 0.0
            }
            
        for currency, data in currencies.items():
            # Add to daily totals
            daily_data[day]['purchases'] += data['total_purchase_amount']
            daily_data[day]['sales'] += data['total_sale_amount']
            
            # Calculate average rates
            avg_purchase_rate = (data['total_purchase_amount'] / data['total_purchased'] 
                               if data['total_purchased'] > 0 else 0)
            avg_sale_rate = (data['total_sale_amount'] / data['total_sold']
                           if data['total_sold'] > 0 else 0)
            
            # Calculate profit based on rate difference
            profit = (avg_sale_rate - avg_purchase_rate) * data['total_sold']
            daily_data[day]['profit'] += profit
    
    # Convert to list and sort by day
    result = list(daily_data.values())
    result.sort(key=lambda x: x['day'])
    
    # Debug log the results
    logger.info(f"Daily data calculated for {len(result)} days")
    if result:
        logger.info(f"Sample day data: {result[0]}")
    
    return jsonify(result)

@app.route('/api/analytics/pie-chart-data', methods=['GET'])
def pie_chart_data():
    from_date = request.args.get('from_date')
    to_date = request.args.get('to_date')
    
    if not from_date or not to_date:
        return jsonify({"error": "Both from_date and to_date are required"}), 400
    
    try:
        from_date_obj = datetime.fromisoformat(from_date.replace('Z', '+00:00'))
        to_date_obj = datetime.fromisoformat(to_date.replace('Z', '+00:00'))
    except ValueError:
        return jsonify({"error": "Invalid date format"}), 400
    
    # Get history entries within date range
    entries = History.query.filter(
        History.created_at >= from_date_obj,
        History.created_at <= to_date_obj
    ).all()
    
    # Calculate purchase and sale data by currency
    purchases_by_currency = {}
    sales_by_currency = {}
    
    for entry in entries:
        if entry.currency_code == 'SOM':
            continue  # Skip SOM currency
            
        if entry.operation_type == 'Purchase':
            if entry.currency_code not in purchases_by_currency:
                purchases_by_currency[entry.currency_code] = 0.0
            purchases_by_currency[entry.currency_code] += entry.total
        elif entry.operation_type == 'Sale':
            if entry.currency_code not in sales_by_currency:
                sales_by_currency[entry.currency_code] = 0.0
            sales_by_currency[entry.currency_code] += entry.total
    
    # Format data for pie chart
    purchases_data = [
        {'currency_code': code, 'total_value': amount}
        for code, amount in purchases_by_currency.items()
    ]
    
    sales_data = [
        {'currency_code': code, 'total_value': amount}
        for code, amount in sales_by_currency.items()
    ]
    
    return jsonify({
        'purchases': purchases_data,
        'sales': sales_data
    })

@app.route('/api/analytics/profitable-currencies', methods=['GET'])
def profitable_currencies():
    from_date = request.args.get('from_date')
    to_date = request.args.get('to_date')
    
    if not from_date or not to_date:
        return jsonify({"error": "Both from_date and to_date are required"}), 400
    
    try:
        from_date_obj = datetime.fromisoformat(from_date.replace('Z', '+00:00'))
        to_date_obj = datetime.fromisoformat(to_date.replace('Z', '+00:00'))
    except ValueError:
        return jsonify({"error": "Invalid date format"}), 400
    
    # Get currencies and calculate profits
    currencies = Currency.query.filter(Currency.code != 'SOM').all()
    
    result = []
    for currency in currencies:
        # Get purchase statistics
        purchases = History.query.filter(
            History.currency_code == currency.code,
            History.operation_type == 'Purchase',
            History.created_at >= from_date_obj,
            History.created_at <= to_date_obj
        ).all()
        
        total_purchased = sum(p.quantity for p in purchases)
        total_purchase_amount = sum(p.total for p in purchases)
        avg_purchase_rate = total_purchase_amount / total_purchased if total_purchased > 0 else 0
        
        # Get sale statistics
        sales = History.query.filter(
            History.currency_code == currency.code,
            History.operation_type == 'Sale',
            History.created_at >= from_date_obj,
            History.created_at <= to_date_obj
        ).all()
        
        total_sold = sum(s.quantity for s in sales)
        total_sale_amount = sum(s.total for s in sales)
        avg_sale_rate = total_sale_amount / total_sold if total_sold > 0 else 0
        
        # Calculate profit
        profit = (avg_sale_rate - avg_purchase_rate) * total_sold
        
        if purchases or sales:
            result.append({
                'currency_code': currency.code,
                'profit': profit,
                'avg_purchase_rate': avg_purchase_rate,
                'avg_sale_rate': avg_sale_rate,
                'total_purchased': total_purchased,
                'total_sold': total_sold
            })
    
    # Sort by profit (descending)
    result.sort(key=lambda x: x['profit'], reverse=True)
    
    return jsonify(result)

@app.route('/api/analytics/batch-data', methods=['GET'])
def batch_analytics_data():
    from_date = request.args.get('from_date')
    to_date = request.args.get('to_date')
    
    if not from_date or not to_date:
        return jsonify({"error": "Both from_date and to_date are required"}), 400
    
    try:
        # Get pie chart data
        pie_chart_response = pie_chart_data()
        pie_chart_data_json = pie_chart_response.json if hasattr(pie_chart_response, 'json') else json.loads(pie_chart_response.data)
        
        # Get profit data
        profit_response = profitable_currencies()
        profit_data_json = profit_response.json if hasattr(profit_response, 'json') else json.loads(profit_response.data)
        
        # Get bar chart data
        bar_chart_response = daily_data()
        bar_chart_data_json = bar_chart_response.json if hasattr(bar_chart_response, 'json') else json.loads(bar_chart_response.data)
        
        return jsonify({
            'pieChartData': pie_chart_data_json,
            'profitData': profit_data_json,
            'barChartData': bar_chart_data_json
        })
    except Exception as e:
        logger.error(f"Error in batch analytics: {str(e)}")
        return jsonify({
            'pieChartData': {'purchases': [], 'sales': []},
            'profitData': [],
            'barChartData': []
        })

# Heartbeat endpoint for connection checking
@app.route('/', methods=['GET'])
def heartbeat():
    return jsonify({
        "status": "online",
        "timestamp": datetime.utcnow().isoformat(),
        "message": "Currency Changer API is running"
    })

if __name__ == '__main__':
    # Create database directory if it doesn't exist
    db_dir = os.path.dirname(app.config['SQLALCHEMY_DATABASE_URI'].replace('sqlite:///', ''))
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir)
    
    # Run the app
    app.run(debug=True, host='0.0.0.0')