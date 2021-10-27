'use strict';

const Boom = require('@hapi/boom');
const uuid = require('node-uuid');
const Joi = require('@hapi/joi');

module.exports = {
    "name": "ApiPlugin",
    "register": async (server, options) => {
		const db = server.app.db;

		var getBooks = () => {
		  return new Promise((resolve, reject) => {
			db.books.find((err, docs) => {
			  if (err) {
				reject(err);
			  } else {
				resolve(docs);
			  }
			});
		  });
		}

		var getBookById = (id) => {
		  return new Promise((resolve, reject) => {
			db.books.findOne({
			  _id: id
			}, (err, doc) => {
			  if (err) {
				reject(err);
			  } else if (!doc) {
				reject('not found');
			  } else {
				resolve(doc);
			  }
			})
		  })
		}

		var setBook = (specimen) => {
		  return new Promise((resolve, reject) => {
			db.books.save(specimen, (err, result) => {
			  if (err) {
				reject(err);
			  } else {
				resolve(result);
			  }
			})
		  })
		}

		var updateBook = (id, specimen) => {
		  return new Promise((resolve, reject) => {
			db.books.update({
			  _id: id
			}, {
			  $set: specimen
			}, (err, result) => {
			  if (err) {
				reject(err);
			  } else {
				resolve(result);
			  }
			})
		  })
		}

		var removeBook = (id) => {
		  return new Promise((resolve, reject) => {
			db.books.remove({
			  _id: id
			}, (err, result) => {
			  if (err) {
				reject(err);
			  } else {
				resolve(result);
			  }
			})
		  })
		}

		server.route({
			method: 'GET',
			path: '/books',  
			handler: async (request, h) => {
				console.log('Do a GET/books');
				try {
					var documents = await getBooks();
					const response = h.response(documents);
					response.code = 200;
					return response;
				} catch (e) {
					const response = h.response(e.message);
					response.code = 500;
					return response;
				}
			}
		});

		server.route({
			method: 'GET',
			path: '/books/{id}',
			handler: async (request, h) => {
				console.log('Do a GET/books/{id}');
				try {
					var documents = await getBookById(request.params.id);
					const response = h.response(documents);
					response.code = 200;
					return response;
				} catch (e) {
					const response = h.response(e.message);
					response.code = 500;
					return response;
				}
			}
		});

		server.route({
			method: 'POST',
			path: '/books',
			handler: async (request, h) => {
				console.log('Do a POST/books');
				const book = request.payload;
				//Create an id
				book._id = uuid.v1();
				try {
					console.log(book);
					var documents = await setBook(book);
					const response = h.response(documents);
					response.code = 200;
					return response;
				} 	
				catch (e) {
						const response = h.response(e.message);
						response.code = 500;
						return response;
				}
			},
			options: {
				validate: {
					payload: Joi.object({
							title: Joi.string().min(10).max(50).required(),
							author: Joi.string().min(10).max(50).required(),
							isbn: Joi.number()
						})
				}
			}
		});

		server.route({
			method: 'PATCH',
			path: '/books/{id}',
			handler: async (request, h) => {
				try {
					//console.log(request.payload);
					//console.log(request.params.id);
					var documents = await updateBook(request.params.id, request.payload);
					const response = h.response(documents);
					response.code = 200;
					return response;
				} catch (e) {
					const response = h.response(e.message);
					response.code = 500;
					return response;
				}
			},
			options : {
				validate: {
					payload: Joi.object({
						title: Joi.string().min(10).max(50).optional(),
						author: Joi.string().min(10).max(50).optional(),
						isbn: Joi.number().optional()
					}).required().min(1)
				}
			}
		});

		server.route({
			method: 'DELETE',
			path: '/books/{id}',
			handler: async (request, h) => {
				try {
					console.log(request.params.id);
					var documents = await removeBook(request.params.id);
					const response = h.response(documents);
					response.code = 200;
					return response;
				} catch (e) {
					const response = h.response(e.message);
					response.code = 500;
					return response;
				}
			}
		})
	}
}